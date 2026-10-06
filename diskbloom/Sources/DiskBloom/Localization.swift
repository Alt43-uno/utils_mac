import Foundation

enum Language: String, CaseIterable { case system, ru, en }

enum L {
    static var language: Language { Language(rawValue: UserDefaults.standard.string(forKey: "language") ?? "system") ?? .system }
    static var russian: Bool { language == .ru || (language == .system && Locale.preferredLanguages.first?.hasPrefix("ru") == true) }
    static func text(_ english: String, _ russian: String) -> String { self.russian ? russian : english }
    static var scan: String { text("Scan", "Сканировать") }
    static var rescan: String { text("Rescan", "Повторить") }
    static var cancel: String { text("Cancel", "Отмена") }
    static var folder: String { text("Scan folder…", "Выбрать папку…") }
    static var overview: String { text("Disks & folders", "Диски и папки") }
    static var collection: String { text("Collection", "Коллекция") }
    static var preview: String { text("Quick Look", "Быстрый просмотр") }
    static var reveal: String { text("Show in Finder", "Показать в Finder") }
    static var collect: String { text("Add to collection", "В коллекцию") }
    static var allocated: String { text("Size on disk", "На диске") }
    static var logical: String { text("Logical size", "Размер файлов") }
    static var settings: String { text("Settings", "Настройки") }
    static var largest: String { text("Largest files", "Крупные файлы") }
    static var snapshots: String { text("Snapshots", "Снимки APFS") }
    static var cloud: String { text("Cloud storage", "Облачные диски") }
    static var access: String { text("Full Disk Access", "Полный доступ к диску") }
}
