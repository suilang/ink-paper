import Foundation
import ServiceManagement

@MainActor
final class ConfigStore: ObservableObject {
    @Published private(set) var config: AppConfig

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("InkPaper", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("config.json")

        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let data = try Data(contentsOf: fileURL)
                config = try decoder.decode(AppConfig.self, from: data)
            } catch {
                let backup = dir.appendingPathComponent("config.corrupt.\(Int(Date().timeIntervalSince1970)).json")
                try? fileManager.copyItem(at: fileURL, to: backup)
                config = .default
                persist()
            }
        } else {
            config = .default
            persist()
        }
    }

    func update(_ mutate: (inout AppConfig) -> Void) {
        var next = config
        mutate(&next)
        // Hard constraints
        next.ignoreMouseEvents = true
        next.hideOnAppQuit = true
        config = next
        persist()
    }

    func replace(_ newConfig: AppConfig) {
        var next = newConfig
        next.ignoreMouseEvents = true
        next.hideOnAppQuit = true
        config = next
        persist()
    }

    func persist() {
        let snapshot = config
        let url = fileURL
        DispatchQueue.global(qos: .utility).async {
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: [.atomic])
            } catch {
                NSLog("InkPaper: failed to persist config: \(error)")
            }
        }
    }

    func applyLaunchAtLogin() {
        if #available(macOS 13.0, *) {
            do {
                if config.launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                NSLog("InkPaper: launch at login failed: \(error)")
            }
        }
    }
}
