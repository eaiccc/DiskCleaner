//
//  RuleEngine.swift
//  DiskCleaner
//
//  Evaluates declarative cleanup rules (rules.json) against the filesystem.
//

import Foundation

nonisolated struct RuleEngine: Sendable {
    let rules: [CleanupRule]
    let home: String
    let tmpDir: String
    let excluded: [String]
    /// Candidates smaller than this are ignored (empty cache folders etc.).
    var minimumSize: Int64 = 64 * 1024

    /// (rule index, fully expanded pattern) pairs used for classification.
    private let expandedPatterns: [(Int, String)]

    init(rules: [CleanupRule] = RuleEngine.builtInRules, home: String = PathUtils.home,
         tmpDir: String = PathUtils.tmpDir, excluded: [String] = []) {
        self.rules = rules
        self.home = home
        self.tmpDir = PathUtils.trimTrailingSlash(tmpDir)
        self.excluded = excluded
        var patterns: [(Int, String)] = []
        for (index, rule) in rules.enumerated() {
            for raw in rule.paths {
                for p in PathUtils.expandBraces(raw) {
                    patterns.append((index, RuleEngine.expandVariables(p, home: home, tmpDir: self.tmpDir)))
                }
            }
        }
        self.expandedPatterns = patterns
    }

    // MARK: - Rule loading

    static let builtInRules: [CleanupRule] = loadRules()

    static func loadRules(bundle: Bundle = .main) -> [CleanupRule] {
        let candidates = [bundle, Bundle(for: AppStore.self), Bundle.main]
        for b in candidates {
            if let url = b.url(forResource: "rules", withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let file = try? JSONDecoder().decode(RuleFile.self, from: data) {
                return file.rules
            }
        }
        // Fallback for tests when bundle resources are outside test host
        let localFallbacks = [
            "DiskCleaner/Resources/rules.json",
            "../DiskCleaner/Resources/rules.json"
        ]
        for relative in localFallbacks {
            if let data = try? Data(contentsOf: URL(fileURLWithPath: relative)),
               let file = try? JSONDecoder().decode(RuleFile.self, from: data) {
                return file.rules
            }
        }
        print("RuleEngine [ERROR]: rules.json not found in any bundle or fallback path")
        return []
    }

    // MARK: - Pattern helpers

    static func expandVariables(_ pattern: String, home: String, tmpDir: String) -> String {
        var p = pattern
        if p == "~" || p.hasPrefix("~/") { p = home + p.dropFirst() }
        return p.replacingOccurrences(of: "$TMPDIR", with: tmpDir)
    }

    static func glob(_ pattern: String) -> [String] {
        var gt = glob_t()
        defer { globfree(&gt) }
        guard Darwin.glob(pattern, 0, nil, &gt) == 0 else { return [] }
        var paths: [String] = []
        for i in 0..<Int(gt.gl_pathc) {
            if let cString = gt.gl_pathv[i] { paths.append(String(cString: cString)) }
        }
        return paths
    }

    private func isExcluded(_ path: String) -> Bool {
        excluded.contains { PathUtils.isSameOrInside(path, $0) }
    }

    /// The first rule whose pattern matches `path` or one of its ancestors.
    func classify(_ path: String) -> CleanupRule? {
        for (index, pattern) in expandedPatterns {
            if fnmatch(pattern, path, 0) == 0 || fnmatch(pattern + "/*", path, 0) == 0 {
                return rules[index]
            }
        }
        return nil
    }

    // MARK: - Evaluation

    /// Expands every rule, measures each match and returns cleanup candidates.
    /// Earlier rules win: a path already claimed (or inside a claimed path) is skipped by later rules.
    func evaluate(now: Date = Date(), progress: (@Sendable (String) -> Void)? = nil) -> [CleanupCandidate] {
        var claimed: [String] = []
        var result: [CleanupCandidate] = []
        for rule in rules where rule.classifyOnly != true {
            progress?(rule.name)
            for raw in rule.paths {
                for pattern in PathUtils.expandBraces(raw) {
                    let expanded = RuleEngine.expandVariables(pattern, home: home, tmpDir: tmpDir)
                    for path in RuleEngine.glob(expanded) {
                        if Task.isCancelled { return result }
                        if claimed.contains(where: { PathUtils.isSameOrInside(path, $0) }) || isExcluded(path) { continue }
                        guard PathGuard.isDeletionAllowed(path, home: home, tmpDir: tmpDir) else { continue }
                        let m = FS.measure(path)
                        guard m.size >= minimumSize else { continue }
                        if let days = rule.minAgeDays, let newest = m.newest,
                           now.timeIntervalSince(newest) < Double(days) * 86_400 {
                            continue
                        }
                        claimed.append(path)
                        result.append(makeCandidate(rule: rule, path: path, measurement: m))
                    }
                }
            }
        }
        return result
    }

    private func makeCandidate(rule: CleanupRule, path: String, measurement m: Measurement) -> CleanupCandidate {
        let (name, detail) = describe(rule: rule, path: path)
        return CleanupCandidate(path: path, name: name, detail: detail, size: m.size, lastModified: m.newest,
                                safety: rule.safety, category: rule.category, ruleID: rule.id,
                                ruleName: rule.name, note: rule.note, runningApps: rule.runningApps ?? [])
    }

    private func describe(rule: CleanupRule, path: String) -> (String, String) {
        let last = PathUtils.lastComponent(path)
        let parent = PathUtils.lastComponent(PathUtils.parent(path))
        let shortPath = PathUtils.abbreviate(path, home: home)
        switch rule.nameStyle {
        case "derivedData":
            var name = last
            if let range = last.range(of: "-[a-z]{28}$", options: .regularExpression) {
                name.removeSubrange(range)
            }
            if let info = NSDictionary(contentsOfFile: PathUtils.join(path, "info.plist")),
               let workspace = info["WorkspacePath"] as? String {
                return (name, PathUtils.abbreviate(workspace, home: home))
            }
            return (name, shortPath)
        case "archive":
            var name = last.replacingOccurrences(of: ".xcarchive", with: "")
            if let info = NSDictionary(contentsOfFile: PathUtils.join(path, "Info.plist")),
               let appName = info["Name"] as? String {
                let props = info["ApplicationProperties"] as? [String: Any]
                let version = props?["CFBundleShortVersionString"] as? String ?? ""
                let build = props?["CFBundleVersion"] as? String ?? ""
                name = version.isEmpty ? appName : "\(appName) \(version) (\(build))"
            }
            return (name, "封存於 \(parent)")
        case "huggingface":
            let parts = last.components(separatedBy: "--")
            if parts.count >= 3 {
                return (parts.dropFirst().joined(separator: "/"), "\(parts[0]) · \(shortPath)")
            }
            return (last, shortPath)
        case "parentAndLast":
            return ("\(parent) / \(last)", shortPath)
        case "iosBackup":
            if let info = NSDictionary(contentsOfFile: PathUtils.join(path, "Info.plist")) {
                let device = info["Device Name"] as? String ?? String(last.prefix(8))
                let product = info["Product Version"] as? String ?? ""
                return (device, product.isEmpty ? shortPath : "iOS \(product) · \(shortPath)")
            }
            return (String(last.prefix(12)), shortPath)
        default:
            return (last, shortPath)
        }
    }
}
