import SwiftUI
import DiskBloomCore

@MainActor
final class CloudConnection: ObservableObject {
    @Published var provider = "drive"
    @Published var name = ""
    @Published var busy = false
    @Published var state = ""
    @Published var question = ""
    @Published var answer = ""
    @Published var choices: [(String, String)] = []
    @Published var secret = false
    @Published var error: String?
    @Published var finished = false
    private var token = CancellationToken()
    private var createdName: String?
    let bridge: CloudBridge?
    init(bridge: CloudBridge?) { self.bridge = bridge }
    func start() {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil else {
            error = L.text("Use letters, numbers, hyphens or underscores for the account name.", "Название аккаунта: латинские буквы, цифры, дефисы или подчёркивания."); return
        }
        guard let bridge else { return }
        busy = true; error = nil
        Task {
            do {
                let existing = try await Task.detached { try bridge.remotes() }.value
                guard !existing.contains(clean + ":") else { busy = false; error = L.text("This account name already exists.", "Такое название аккаунта уже существует."); return }
                createdName = clean
                var args = ["config", "create", clean, provider, "--non-interactive"]
                if provider == "drive" { args += ["scope", "drive"] }
                run(args)
            } catch { busy = false; self.error = error.localizedDescription }
        }
    }
    func next() {
        guard let name = createdName else { return }
        run(["config", "update", name, "--non-interactive", "--continue", "--state", state, "--result", answer])
    }
    private func run(_ args: [String]) {
        guard let bridge else { return }; busy = true; error = nil
        let token = self.token
        Task {
            do {
                let data = try await Task.detached { try bridge.command(args, token: token, timeout: 900) }.value
                guard !token.isCancelled else { cleanup(); return }
                guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw BloomError.message("Invalid authorization response") }
                state = result["State"] as? String ?? ""
                if state.isEmpty {
                    finished = true; busy = false
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bridge.configPath)
                    return
                }
                let option = result["Option"] as? [String: Any] ?? [:]
                question = option["Help"] as? String ?? option["Name"] as? String ?? ""
                choices = (option["Examples"] as? [[String: Any]] ?? []).compactMap {
                    guard let v = $0["Value"] as? String else { return nil }; return (v, $0["Help"] as? String ?? v)
                }
                if let value = option["Default"] { answer = String(describing: value) } else { answer = "" }
                secret = option["IsPassword"] as? Bool ?? false
                error = (result["Error"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                busy = false
            } catch {
                busy = false
                if token.isCancelled { cleanup() } else { self.error = error.localizedDescription }
            }
        }
    }
    func cancel() { token.cancel(); if !busy { cleanup() } }
    private func cleanup() {
        guard !finished, let name = createdName, let bridge else { return }
        createdName = nil
        Task.detached { _ = try? bridge.command(["config", "delete", name]) }
    }
}

struct CloudConnectView: View {
    @ObservedObject var model: AppModel
    @StateObject private var connection: CloudConnection
    init(model: AppModel) { self.model = model; _connection = StateObject(wrappedValue: CloudConnection(bridge: model.cloudBridge)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack { Text(L.text("Connect cloud storage", "Подключить облачный диск")).font(.system(size: 24, weight: .semibold)); Spacer(); Image(systemName: "cloud").font(.system(size: 28)).foregroundStyle(Theme.accent) }
            if connection.finished {
                Label(L.text("Account connected", "Аккаунт подключён"), systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent).font(.system(size: 17, weight: .medium)).padding(.vertical, 25)
            } else if connection.state.isEmpty && !connection.busy {
                Picker(L.text("Service", "Сервис"), selection: $connection.provider) {
                    Text("Google Drive").tag("drive"); Text("Dropbox").tag("dropbox"); Text("Microsoft OneDrive").tag("onedrive"); Text("Box").tag("box")
                }
                TextField(L.text("Account name (e.g. personal-drive)", "Название аккаунта (например personal-drive)"), text: $connection.name).textFieldStyle(.roundedBorder)
                Text(L.text("Authorization opens in your browser. DiskBloom uses rclone's OAuth application. Your password is never entered into DiskBloom.", "Авторизация откроется в браузере через OAuth-приложение rclone. Пароль аккаунта не вводится в DiskBloom."))
                    .font(.system(size: 12)).foregroundStyle(Theme.secondary).lineSpacing(4)
            } else if connection.busy {
                HStack(spacing: 15) { ProgressView(); Text(L.text("Follow the authorization steps in your browser…", "Следуйте шагам авторизации в браузере…")).font(.system(size: 13)) }.padding(.vertical, 30)
                Text(L.text("You can cancel here if the provider does not respond.", "Если провайдер не отвечает, можно отменить подключение здесь.")).font(.system(size: 11)).foregroundStyle(Theme.muted)
            } else {
                ScrollView { Text(connection.question).font(.system(size: 12)).foregroundStyle(Theme.secondary).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 160)
                if !connection.choices.isEmpty {
                    Picker(L.text("Choose", "Выберите"), selection: $connection.answer) {
                        ForEach(connection.choices, id: \.0) { choice in Text(choice.1).tag(choice.0) }
                    }
                }
                if connection.secret { SecureField(L.text("Answer", "Ответ"), text: $connection.answer).textFieldStyle(.roundedBorder) }
                else { TextField(L.text("Answer", "Ответ"), text: $connection.answer).textFieldStyle(.roundedBorder) }
            }
            if let error = connection.error { Text(error).font(.system(size: 11)).foregroundStyle(Color(hex: 0xF2A6BA)).textSelection(.enabled) }
            HStack {
                Spacer()
                if connection.finished {
                    Button(L.text("Done", "Готово")) { model.refreshCloud(); model.showCloudConnect = false }.buttonStyle(BloomButtonStyle(prominent: true))
                } else {
                    Button(L.cancel) { connection.cancel(); model.showCloudConnect = false }.buttonStyle(BloomButtonStyle())
                    Button(connection.state.isEmpty ? L.text("Connect", "Подключить") : L.text("Continue", "Продолжить")) {
                        if connection.state.isEmpty { connection.start() } else { connection.next() }
                    }.buttonStyle(BloomButtonStyle(prominent: true)).disabled(connection.busy)
                }
            }
        }.padding(30).frame(width: 550).background(Theme.background).foregroundStyle(Theme.text)
            .onDisappear { if !connection.finished { connection.cancel() } }
    }
}
