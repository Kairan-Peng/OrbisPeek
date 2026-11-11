import Foundation
import Darwin

public enum ExtensionRegistrationState: String, Codable, Sendable {
    case preferred, defaultElection, ignored, debugger, superseded, unknown
    case unregistered, unavailable, differentCopy

    public var title: String {
        switch self {
        case .preferred: return "已选择使用"
        case .defaultElection: return "由系统选择"
        case .ignored: return "已停用"
        case .debugger: return "仅调试使用"
        case .superseded: return "已被另一版本替代"
        case .unknown: return "状态未知"
        case .unregistered: return "尚未登记"
        case .unavailable: return "系统状态暂不可读取"
        case .differentCopy: return "登记的是另一份应用"
        }
    }
}

public enum ExtensionInstallationLocation: String, Codable, Sendable {
    case applications, development, diskImage, other

    public var title: String {
        switch self {
        case .applications: return "已放入应用程序目录"
        case .development: return "正在运行开发构建"
        case .diskImage: return "正在从磁盘映像运行"
        case .other: return "建议移入应用程序目录"
        }
    }
}

public struct RegisteredQuickLookExtension: Codable, Sendable, Identifiable, Equatable {
    public let identifier: String
    public let version: String
    public let path: String
    public let registrationID: String
    public let election: ExtensionRegistrationState
    public var id: String { registrationID + "|" + path }
    public var appName: String {
        let components = URL(fileURLWithPath: path).pathComponents
        return components.last(where: { $0.hasSuffix(".app") }).map { String($0.dropLast(4)) }
            ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
    }
}

public struct QuickLookExtensionConflict: Codable, Sendable, Identifiable, Equatable {
    public let plugin: RegisteredQuickLookExtension
    public let overlappingTypes: [String]
    public var id: String { plugin.id }
    public var displayName: String { plugin.appName }
}

public struct ExtensionDiagnosticsSnapshot: Codable, Sendable {
    public let checkedAt: Date
    public let hostPath: String
    public let extensionPath: String
    public let extensionPresent: Bool
    public let installation: ExtensionInstallationLocation
    public let querySucceeded: Bool
    public let queryError: String?
    public let registration: ExtensionRegistrationState
    public let ownRegistrations: [RegisteredQuickLookExtension]
    public let conflicts: [QuickLookExtensionConflict]
    public let unreadablePluginCount: Int
    public let guidance: [String]
}

/// A read-only development diagnostic. PlugInKit elections are not a promise
/// that Finder selected a provider. A sandbox-rejected query is always unknown.
public enum ExtensionDiagnostics {
    public static let extensionIdentifier = "org.quicklook.preview.extension"

    public static func snapshot(hostURL: URL = Bundle.main.bundleURL) async -> ExtensionDiagnosticsSnapshot {
        await Task.detached(priority: .utility) {
            makeSnapshot(hostURL: hostURL, result: runRegistryQuery())
        }.value
    }

    struct RegistryQueryResult {
        let output: String
        let exitCode: Int32?
        let error: String?
    }

    struct RegistryParseResult {
        let entries: [RegisteredQuickLookExtension]
        let isRecognized: Bool
    }

    static func parseRegistryOutput(_ output: String) -> RegistryParseResult {
        let expression = try! NSRegularExpression(
            pattern: #"^\s*([+\-!?=]?)\s*([A-Za-z0-9][A-Za-z0-9._-]*)\(([^)]*)\)\t([^\t]+)\t[^\t]+\t(.+)$"#
        )
        let summary = try! NSRegularExpression(pattern: #"^\s*\((\d+) plug-ins?\)\s*$"#)
        var entries: [RegisteredQuickLookExtension] = []
        var summaryCount: Int?
        for line in output.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            if let match = summary.firstMatch(in: line, range: range),
               let countRange = Range(match.range(at: 1), in: line) {
                summaryCount = Int(line[countRange])
            }
            guard let match = expression.firstMatch(in: line, range: range) else { continue }
            func group(_ number: Int) -> String {
                Range(match.range(at: number), in: line).map { String(line[$0]) } ?? ""
            }
            let election: ExtensionRegistrationState
            switch group(1) {
            case "+": election = .preferred
            case "-": election = .ignored
            case "!": election = .debugger
            case "=": election = .superseded
            case "?": election = .unknown
            default: election = .defaultElection
            }
            let path = group(5).trimmingCharacters(in: .whitespaces)
            guard path.hasPrefix("/"), path.hasSuffix(".appex") else { continue }
            entries.append(RegisteredQuickLookExtension(
                identifier: group(2), version: group(3), path: path,
                registrationID: group(4), election: election
            ))
        }
        let recognized = summaryCount.map { $0 == entries.count } ?? !entries.isEmpty
        return RegistryParseResult(entries: entries, isRecognized: recognized)
    }

    static func installationLocation(for hostURL: URL) -> ExtensionInstallationLocation {
        let path = hostURL.standardizedFileURL.path
        if path.hasPrefix("/Volumes/") { return .diskImage }
        if path.contains("/.build/") || path.contains("/DerivedData/") { return .development }
        if path.hasPrefix("/Applications/") || userApplicationsPath.map({ path.hasPrefix($0 + "/") }) == true {
            return .applications
        }
        return .other
    }

    // Foundation's home-directory API returns the app's container in a sandbox.
    // Account metadata is needed only to classify ~/Applications; no files are read.
    private static var userApplicationsPath: String? {
        let capacity = 16 * 1024
        var buffer = [CChar](repeating: 0, count: capacity)
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        guard getpwuid_r(getuid(), &entry, &buffer, capacity, &result) == 0,
              result != nil, let directory = entry.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: directory)).appendingPathComponent("Applications").path
    }

    static func makeSnapshot(hostURL: URL, result: RegistryQueryResult) -> ExtensionDiagnosticsSnapshot {
        let extensionURL = hostURL.appendingPathComponent("Contents/PlugIns/QuicklookPreview.appex")
        let extensionPresent = FileManager.default.fileExists(atPath: extensionURL.path)
        let parsed = parseRegistryOutput(result.output)
        let querySucceeded = result.exitCode == 0 && result.error == nil && parsed.isRecognized
        let own = querySucceeded ? parsed.entries.filter { $0.identifier == extensionIdentifier } : []
        let local = own.first { canonical($0.path) == canonical(extensionURL.path) }
        let registration: ExtensionRegistrationState
        if !querySucceeded { registration = .unavailable }
        else if let local { registration = local.election }
        else { registration = own.isEmpty ? .unregistered : .differentCopy }

        var unreadable = 0
        var conflicts: [QuickLookExtensionConflict] = []
        if querySucceeded {
            let supported = Set(FileTypeRegistry.supportedUTIs)
            for entry in parsed.entries where entry.identifier != extensionIdentifier {
                guard !entry.identifier.hasPrefix("com.apple."),
                      ![.ignored, .superseded].contains(entry.election) else { continue }
                guard let plist = readInfo(at: URL(fileURLWithPath: entry.path)) else {
                    unreadable += 1
                    continue
                }
                let info = plist["NSExtension"] as? [String: Any]
                let attributes = info?["NSExtensionAttributes"] as? [String: Any]
                let types = attributes?["QLSupportedContentTypes"] as? [String] ?? []
                let overlap = supported.intersection(types).sorted()
                if !overlap.isEmpty {
                    conflicts.append(QuickLookExtensionConflict(plugin: entry, overlappingTypes: overlap))
                }
            }
        }

        let installation = installationLocation(for: hostURL)
        var guidance: [String] = []
        if !extensionPresent { guidance.append("应用中的预览扩展缺失，请重新安装完整的 Quicklook.app。") }
        if installation != .applications { guidance.append("将 Quicklook.app 移入应用程序目录后打开一次，再前往系统设置检查快速查看扩展。") }
        switch registration {
        case .unavailable:
            guidance.append("当前进程无法读取系统扩展登记状态；这不代表扩展未启用。请在系统设置中检查，并用样本的 Space 预览确认。")
        case .ignored:
            guidance.append("请在系统设置的快速查看扩展中启用 Quicklook。")
        case .unregistered, .differentCopy:
            guidance.append("请打开当前安装位置的 Quicklook，并检查是否保留了旧版本或另一份副本。")
        case .debugger, .superseded, .unknown:
            guidance.append("当前登记状态需要核对；请使用安装后的应用，并在系统设置中检查快速查看扩展。")
        case .preferred, .defaultElection:
            guidance.append("登记状态不能证明 Finder 最终选择了本扩展，请使用样本进行实际预览。")
        }
        if own.count > 1 { guidance.append("系统登记了多份 Quicklook 预览扩展；建议只保留应用程序目录中的正式安装副本。") }
        if !conflicts.isEmpty { guidance.append("发现支持相同文件类型的其他扩展；若显示的不是 Quicklook，请在系统设置中选择要使用的扩展。") }
        if unreadable > 0 { guidance.append("部分扩展信息无法读取，当前冲突检查可能不完整。") }

        let queryError: String?
        if querySucceeded { queryError = nil }
        else if let error = result.error { queryError = error }
        else if !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryError = String(result.output.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        } else { queryError = "系统诊断命令没有返回可识别的登记信息。" }

        return ExtensionDiagnosticsSnapshot(
            checkedAt: Date(), hostPath: hostURL.path, extensionPath: extensionURL.path,
            extensionPresent: extensionPresent, installation: installation,
            querySucceeded: querySucceeded, queryError: queryError, registration: registration,
            ownRegistrations: own,
            conflicts: conflicts.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending },
            unreadablePluginCount: unreadable, guidance: guidance
        )
    }

    private static func readInfo(at bundleURL: URL) -> [String: Any]? {
        let url = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 1024 * 1024,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 1024 * 1024 + 1), data.count <= 1024 * 1024,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist
    }

    private static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private static func runRegistryQuery() -> RegistryQueryResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-m", "-AvD", "-p", "com.apple.quicklook.preview"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let state = QueryTimeoutState()
        let timeout = DispatchWorkItem {
            if process.isRunning {
                state.markTimedOut()
                process.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.5) {
                    if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                }
            }
        }
        do {
            try process.run()
            DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: timeout)
            var data = Data()
            var exceededLimit = false
            while let chunk = try pipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
                if data.count + chunk.count <= 1024 * 1024 { data.append(chunk) }
                else { exceededLimit = true; process.terminate() }
            }
            process.waitUntilExit()
            timeout.cancel()
            return RegistryQueryResult(
                output: String(data: data, encoding: .utf8) ?? "",
                exitCode: process.terminationStatus,
                error: state.timedOut ? "系统扩展查询超时。" : exceededLimit ? "系统扩展查询结果超过大小限制。" : nil
            )
        } catch {
            timeout.cancel()
            return RegistryQueryResult(output: "", exitCode: nil, error: error.localizedDescription)
        }
    }
}

private final class QueryTimeoutState: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var timedOut: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func markTimedOut() { lock.lock(); value = true; lock.unlock() }
}
