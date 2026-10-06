//
//  SimulatorService.swift
//  DiskCleaner
//
//  Lists and deletes simulator devices / runtimes through `xcrun simctl`
//  (never `rm`, so CoreSimulator's device sets stay consistent).
//

import Foundation

nonisolated enum Simctl {
    /// Runs `xcrun <args>` and returns (exit status, stdout, stderr).
    @discardableResult
    static func run(_ args: [String]) -> (status: Int32, output: Data, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = args
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return (-1, Data(), error.localizedDescription)
        }
        // Drain stderr concurrently so a chatty tool can't block on a full pipe.
        let errBox = ErrorBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            errBox.data = err.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        group.wait()
        let message = String(data: errBox.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, data, message)
    }

    private final class ErrorBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _data = Data()
        var data: Data {
            get { lock.withLock { _data } }
            set { lock.withLock { _data = newValue } }
        }
    }
}

nonisolated struct SimulatorService: Sendable {
    let home: String

    init(home: String = PathUtils.home) {
        self.home = home
    }

    private struct Device: Decodable {
        let udid: String
        let name: String
        let state: String?
        let isAvailable: Bool?
        let availabilityError: String?
        let dataPath: String?
        let lastBootedAt: String?
    }

    private struct DeviceList: Decodable {
        let devices: [String: [Device]]
    }

    private struct Runtime: Decodable {
        let identifier: String
        let version: String?
        let build: String?
        let platformIdentifier: String?
        let sizeBytes: Int64?
        let deletable: Bool?
        let lastUsedAt: String?
        let path: String?
    }

    static func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-17-2" → "iOS 17.2"
    static func runtimeName(_ key: String) -> String {
        let last = key.components(separatedBy: ".").last ?? key
        var parts = last.components(separatedBy: "-")
        guard parts.count > 1 else { return last }
        let platform = parts.removeFirst()
        return platform + " " + parts.joined(separator: ".")
    }

    static func platformName(_ identifier: String?) -> String {
        switch identifier {
        case "com.apple.platform.iphonesimulator": return "iOS"
        case "com.apple.platform.appletvsimulator": return "tvOS"
        case "com.apple.platform.watchsimulator": return "watchOS"
        case "com.apple.platform.xrsimulator": return "visionOS"
        default: return "Runtime"
        }
    }

    func deviceCandidates() -> [CleanupCandidate] {
        let result = Simctl.run(["simctl", "list", "devices", "--json"])
        guard result.status == 0,
              let list = try? JSONDecoder().decode(DeviceList.self, from: result.output) else {
            print("SimulatorService [LOG]: simctl list devices unavailable: \(result.error)")
            return []
        }
        let formatter = RelativeDateTimeFormatter()
        var candidates: [CleanupCandidate] = []
        for (runtimeKey, devices) in list.devices {
            let runtime = SimulatorService.runtimeName(runtimeKey)
            for device in devices {
                let directory = device.dataPath.map { PathUtils.parent($0) }
                    ?? "\(home)/Library/Developer/CoreSimulator/Devices/\(device.udid)"
                let m = FS.measure(directory)
                let available = device.isAvailable ?? true
                let lastBooted = SimulatorService.parseDate(device.lastBootedAt)
                let status: String
                if !available {
                    status = "不可用：" + (device.availabilityError ?? "Runtime 已移除")
                } else if let lastBooted {
                    status = "上次啟動 " + formatter.localizedString(for: lastBooted, relativeTo: Date())
                } else {
                    status = "從未啟動"
                }
                candidates.append(CleanupCandidate(
                    path: directory,
                    name: device.name,
                    detail: "\(runtime) · \(status)",
                    size: m.size,
                    lastModified: lastBooted ?? m.newest,
                    safety: available ? .caution : .safe,
                    category: .simulator,
                    ruleID: available ? "simulator.device" : "simulator.unavailable",
                    ruleName: available ? "模擬器裝置" : "不可用的模擬器裝置",
                    note: available ? "透過 simctl 刪除，裝置資料（已安裝的 App、設定）無法復原" : "對應的 Runtime 已移除，可放心刪除",
                    action: .simctlDeleteDevice(udid: device.udid),
                    runningApps: ["com.apple.iphonesimulator"]))
            }
        }
        return candidates
    }

    func runtimeCandidates() -> [CleanupCandidate] {
        let result = Simctl.run(["simctl", "runtime", "list", "-j"])
        guard result.status == 0,
              let runtimes = try? JSONDecoder().decode([String: Runtime].self, from: result.output) else {
            print("SimulatorService [LOG]: simctl runtime list unavailable: \(result.error)")
            return []
        }
        let formatter = RelativeDateTimeFormatter()
        return runtimes.values.compactMap { runtime in
            guard runtime.deletable ?? false, let size = runtime.sizeBytes, size > 0 else { return nil }
            let name = "\(SimulatorService.platformName(runtime.platformIdentifier)) \(runtime.version ?? "")"
            var detail = "Build \(runtime.build ?? "?")"
            let lastUsed = SimulatorService.parseDate(runtime.lastUsedAt)
            if let lastUsed {
                detail += " · 上次使用 " + formatter.localizedString(for: lastUsed, relativeTo: Date())
            }
            return CleanupCandidate(
                id: "simruntime:" + runtime.identifier,
                path: runtime.path ?? "",
                name: name,
                detail: detail,
                size: size,
                lastModified: lastUsed,
                safety: .caution,
                category: .simulator,
                ruleID: "simulator.runtime",
                ruleName: "模擬器 Runtime",
                note: "需要時可在 Xcode → Settings → Components 重新下載",
                action: .simctlDeleteRuntime(identifier: runtime.identifier),
                runningApps: ["com.apple.iphonesimulator", "com.apple.dt.Xcode"])
        }
    }
}
