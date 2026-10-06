//
//  DiskCleanerTests.swift
//  DiskCleanerTests
//
//  Created by Link on 2026/6/3.
//

import Testing
import Foundation
@testable import DiskCleaner

struct DiskCleanerTests {

    @Test func testFormattedSize() async throws {
        let sizeBytes: Int64 = 500
        let sizeKB: Int64 = 1024 * 2        // 2 KB
        let sizeMB: Int64 = 1024 * 1024 * 5 // 5 MB
        let sizeGB: Int64 = 1024 * 1024 * 1024 * 3 // 3 GB

        #expect(sizeBytes.formattedSize().contains("500"))
        #expect(sizeKB.formattedSize().contains("2"))
        #expect(sizeMB.formattedSize().contains("5"))
        #expect(sizeGB.formattedSize().contains("3"))
    }

    @Test func testPathGuardSystemProtection() async throws {
        let home = "/Users/testuser"
        let tmpDir = "/private/var/folders/xx/yyyy/T"

        // Protected system roots (S001)
        #expect(!PathGuard.isDeletionAllowed("/System", home: home, tmpDir: tmpDir))
        #expect(!PathGuard.isDeletionAllowed("/System/Library", home: home, tmpDir: tmpDir))
        #expect(!PathGuard.isDeletionAllowed("/usr", home: home, tmpDir: tmpDir))
        #expect(!PathGuard.isDeletionAllowed("/usr/bin", home: home, tmpDir: tmpDir))
        #expect(!PathGuard.isDeletionAllowed("/bin", home: home, tmpDir: tmpDir))
        #expect(!PathGuard.isDeletionAllowed("/sbin", home: home, tmpDir: tmpDir))
        #expect(!PathGuard.isDeletionAllowed("/private/etc", home: home, tmpDir: tmpDir))

        // Critical user & system folders that must never be deleted as a whole
        #expect(!PathGuard.isDeletionAllowed(home, home: home, tmpDir: tmpDir))
        #expect(!PathGuard.isDeletionAllowed("\(home)/Library", home: home, tmpDir: tmpDir))
        #expect(!PathGuard.isDeletionAllowed("\(home)/Documents", home: home, tmpDir: tmpDir))
        #expect(!PathGuard.isDeletionAllowed("\(home)/Desktop", home: home, tmpDir: tmpDir))
        #expect(!PathGuard.isDeletionAllowed("\(home)/Downloads", home: home, tmpDir: tmpDir))
        #expect(!PathGuard.isDeletionAllowed("\(home)/Library/Developer", home: home, tmpDir: tmpDir))
        #expect(!PathGuard.isDeletionAllowed("\(home)/Library/Developer/Xcode/DerivedData", home: home, tmpDir: tmpDir))

        // Relative path traversal attempts
        #expect(!PathGuard.isDeletionAllowed("/Users/testuser/../System", home: home, tmpDir: tmpDir))
        #expect(!PathGuard.isDeletionAllowed("/", home: home, tmpDir: tmpDir))
    }

    @Test func testPathGuardAllowedCachesAndTmp() async throws {
        let home = "/Users/testuser"
        let tmpDir = "/private/var/folders/xx/yyyy/T"

        // Subdirectories inside DerivedData are allowed
        let projectDerived = "\(home)/Library/Developer/Xcode/DerivedData/MyProject-abcdef"
        #expect(PathGuard.isDeletionAllowed(projectDerived, home: home, tmpDir: tmpDir))

        // Specific cache item
        let cacheItem = "\(home)/Library/Caches/com.apple.dt.Xcode"
        #expect(PathGuard.isDeletionAllowed(cacheItem, home: home, tmpDir: tmpDir))

        // User's own TMPDIR files
        let tmpFile = "\(tmpDir)/test_build_log.txt"
        #expect(PathGuard.isDeletionAllowed(tmpFile, home: home, tmpDir: tmpDir))

        // /private/tmp files
        let sysTmpFile = "/private/tmp/old_test.log"
        #expect(PathGuard.isDeletionAllowed(sysTmpFile, home: home, tmpDir: tmpDir))
    }

    @Test func testPathUtilsBraceExpansion() async throws {
        let pattern = "~/Library/Developer/Xcode/{iOS,watchOS,tvOS} DeviceSupport/*"
        let expanded = PathUtils.expandBraces(pattern)
        #expect(expanded.count == 3)
        #expect(expanded.contains("~/Library/Developer/Xcode/iOS DeviceSupport/*"))
        #expect(expanded.contains("~/Library/Developer/Xcode/watchOS DeviceSupport/*"))
        #expect(expanded.contains("~/Library/Developer/Xcode/tvOS DeviceSupport/*"))

        // Multiple groups
        let pattern2 = "{a,b}/{1,2}"
        let expanded2 = PathUtils.expandBraces(pattern2)
        #expect(expanded2.count == 4)
        #expect(expanded2.contains("a/1"))
        #expect(expanded2.contains("a/2"))
        #expect(expanded2.contains("b/1"))
        #expect(expanded2.contains("b/2"))

        // Plain path
        let plain = "/Library/Logs"
        #expect(PathUtils.expandBraces(plain) == ["/Library/Logs"])
    }

    @Test func testPathUtilsAbbreviate() async throws {
        let home = "/Users/testuser"
        #expect(PathUtils.abbreviate(home, home: home) == "~")
        #expect(PathUtils.abbreviate("\(home)/Documents/file.txt", home: home) == "~/Documents/file.txt")
        #expect(PathUtils.abbreviate("/Applications/Safari.app", home: home) == "/Applications/Safari.app")
    }

    @Test func testRuleEngineJSONLoadingAndClassification() async throws {
        let rules = RuleEngine.loadRules()
        #expect(!rules.isEmpty)

        let engine = RuleEngine(rules: rules, home: "/Users/testuser", tmpDir: "/var/folders/xx/T")

        // Xcode DerivedData item
        let ddPath = "/Users/testuser/Library/Developer/Xcode/DerivedData/MyApp-12345"
        let ruleDD = engine.classify(ddPath)
        #expect(ruleDD != nil)
        #expect(ruleDD?.category == .xcode)
        #expect(ruleDD?.safety == .safe)

        // HuggingFace model
        let hfPath = "/Users/testuser/.cache/huggingface/hub/models--meta-llama--Llama-2-7b"
        let ruleHF = engine.classify(hfPath)
        #expect(ruleHF != nil)
        #expect(ruleHF?.category == .ai)
        #expect(ruleHF?.safety == .caution)

        // Archive
        let archivePath = "/Users/testuser/Library/Developer/Xcode/Archives/2026-06-03/MyApp.xcarchive"
        let ruleArchive = engine.classify(archivePath)
        #expect(ruleArchive != nil)
        #expect(ruleArchive?.category == .xcode)
        #expect(ruleArchive?.safety == .review)
    }

    @Test func testCleanupPlannerDeduplication() async throws {
        let parent = CleanupCandidate(
            path: "/Users/testuser/Library/Developer/Xcode/DerivedData/AppA",
            name: "AppA", detail: "folder", size: 500, lastModified: nil,
            safety: .safe, category: .xcode, ruleID: "xcode.dd", ruleName: "DerivedData"
        )

        let child = CleanupCandidate(
            path: "/Users/testuser/Library/Developer/Xcode/DerivedData/AppA/Build/Products",
            name: "Products", detail: "subfolder", size: 300, lastModified: nil,
            safety: .safe, category: .xcode, ruleID: "xcode.dd", ruleName: "DerivedData"
        )

        let sibling = CleanupCandidate(
            path: "/Users/testuser/Library/Developer/Xcode/DerivedData/AppB",
            name: "AppB", detail: "folder", size: 200, lastModified: nil,
            safety: .safe, category: .xcode, ruleID: "xcode.dd", ruleName: "DerivedData"
        )

        // When both parent and child are selected, child is deduplicated
        let normalized = CleanupPlanner.normalize([parent, child, sibling])
        #expect(normalized.count == 2)
        #expect(normalized.contains { $0.path == parent.path })
        #expect(normalized.contains { $0.path == sibling.path })
        #expect(!normalized.contains { $0.path == child.path })

        #expect(CleanupPlanner.totalSize(normalized) == 700)
    }

    @Test func testFileNodeHierarchyAndRemoval() async throws {
        let child1 = FileNode(name: "sub1", path: "/a/b/sub1", isDirectory: false, size: 100, itemCount: 1, modified: nil)
        let child2 = FileNode(name: "sub2", path: "/a/b/sub2", isDirectory: false, size: 200, itemCount: 1, modified: nil)
        let dir = FileNode(name: "b", path: "/a/b", isDirectory: true, size: 300, itemCount: 2, modified: nil, children: [child1, child2])
        let root = FileNode(name: "a", path: "/a", isDirectory: true, size: 300, itemCount: 3, modified: nil, children: [dir])

        #expect(root.size == 300)
        #expect(root.node(at: "/a/b/sub1")?.size == 100)

        // Remove child1
        let updatedRoot = root.removing(["/a/b/sub1"])
        #expect(updatedRoot != nil)
        #expect(updatedRoot?.size == 200)
        #expect(updatedRoot?.node(at: "/a/b/sub1") == nil)
        #expect(updatedRoot?.node(at: "/a/b/sub2")?.size == 200)
    }

    @Test func testSimulatorServiceHelpers() async throws {
        let parsed = SimulatorService.runtimeName("com.apple.CoreSimulator.SimRuntime.iOS-17-2")
        #expect(parsed == "iOS 17.2")

        let parsedVision = SimulatorService.runtimeName("com.apple.CoreSimulator.SimRuntime.xrOS-1-0")
        #expect(parsedVision == "xrOS 1.0")

        let platform = SimulatorService.platformName("com.apple.platform.iphonesimulator")
        #expect(platform == "iOS")
    }
}

private class BundleToken {}
