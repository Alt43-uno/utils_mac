import AppKit
import Combine
import MouseCraftCore
import UniformTypeIdentifiers

final class SettingsStore: ObservableObject {
    @Published var configuration: Configuration { didSet { save() } }
    @Published var message: String?
    private let url: URL
    private var protectsUnreadableFile = false
    init() {
        url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MouseCraft/settings.json")
        if FileManager.default.fileExists(atPath: url.path) {
            do { configuration = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: url)).validated() }
            catch {
                configuration = Configuration(); protectsUnreadableFile = true
                message = "Не удалось прочитать настройки: \(error.localizedDescription). Перед сохранением исходный файл будет скопирован в settings.backup-*.json."
            }
        } else { configuration = Configuration() }
    }
    private func save() {
        do {
            _ = try configuration.validated()
            if protectsUnreadableFile {
                let backup = url.deletingLastPathComponent().appendingPathComponent("settings.backup-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: url, to: backup)
                protectsUnreadableFile = false
            }
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: url, options: .atomic)
        } catch { message = error.localizedDescription }
    }
    func exportSettings() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "MouseCraft.json"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: destination, options: .atomic)
            message = "Настройки экспортированы."
        } catch { message = error.localizedDescription }
    }
    func importSettings() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            let size = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 2_000_000 else { throw NSError(domain: "MouseCraft", code: 1, userInfo: [NSLocalizedDescriptionKey: "Файл настроек слишком большой."]) }
            var imported = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: source)).validated()
            imported.enabled = false
            configuration = imported; message = "Настройки импортированы. Проверьте назначения и включите MouseCraft."
        } catch { message = error.localizedDescription }
    }
    func addProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return }
        guard !configuration.profiles.contains(where: { $0.bundleID == id }) else { message = "Профиль этого приложения уже существует."; return }
        configuration.profiles.append(AppProfile(name: url.deletingPathExtension().lastPathComponent, bundleID: id))
    }
}
