import SwiftUI
import AppKit

@main
struct DiskBloomApp: App {
    @NSApplicationDelegateAdaptor(BloomDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        Window("DiskBloom", id: "main") {
            ContentView(model: model).onAppear { delegate.model = model }
        }
        .defaultSize(width: 1240, height: 790)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L.folder, action: model.chooseFolder).keyboardShortcut("o")
                Button(L.rescan, action: model.rescan).keyboardShortcut("r").disabled(model.activeJob != nil || model.source == nil)
                Divider()
                Button(L.text("Export report…", "Экспорт отчёта…"), action: model.exportReport).keyboardShortcut("e").disabled(model.report == nil)
            }
            CommandGroup(replacing: .appSettings) { Button(L.settings) { model.page = .settings }.keyboardShortcut(",") }
            CommandMenu(L.text("Navigate", "Навигация")) {
                Button(L.text("Parent folder", "Родительская папка"), action: model.goUp).keyboardShortcut(.upArrow)
                Button(L.text("Back", "Назад"), action: model.goBack).keyboardShortcut("[").disabled(!model.canBack)
                Button(L.text("Forward", "Вперёд"), action: model.goForward).keyboardShortcut("]").disabled(!model.canForward)
                Button(L.overview) { model.page = .overview }.keyboardShortcut("1")
            }
            CommandMenu(L.text("Files", "Файлы")) {
                Button(L.preview) { model.preview() }.keyboardShortcut(.space, modifiers: []).disabled(model.inspected == nil)
                Button(L.reveal) { model.reveal() }.keyboardShortcut("f", modifiers: [.command, .shift])
                Button(L.collect) { model.collect() }.keyboardShortcut(.delete).disabled(model.inspected.map { !model.canCollect($0) } ?? true)
                Button(L.collection) { model.showCollector = true }.keyboardShortcut("k")
            }
            CommandGroup(replacing: .help) {
                Button(L.text("DiskBloom guide", "Руководство DiskBloom")) { model.page = .settings }
            }
        }
    }
}

@MainActor
final class BloomDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model?.isDeleting == true {
            if model?.deletionCountdown != nil { model?.cancelDeletion() }
            else { model?.notify(L.text("Wait for the file operation to finish.", "Дождитесь завершения операции с файлами.")); return .terminateCancel }
        }
        model?.jobs.values.forEach { $0.token.cancel() }
        AppModel.clearPreviewCache()
        return .terminateNow
    }
}
