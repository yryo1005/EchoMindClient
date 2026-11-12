import SwiftUI

/// ログイン・アカウント登録画面．
struct LoginView: View {
    /// 画面のモード．
    private enum Mode: String, CaseIterable, Identifiable {
        case login = "ログイン"
        case register = "新規登録"

        var id: Self { self }
    }

    /// サーバー側と同じパスワードの最小文字数．
    private static let minimumPasswordLength = 8

    @Environment(AuthSession.self) private var authSession
    @AppStorage(AppConfig.serverURLKey) private var serverURLText = ""

    @State private var mode = Mode.login
    @State private var email = ""
    @State private var password = ""
    @State private var passwordConfirmation = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            Form {
                Picker("モード", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                if AppConfig.normalizedServerURL(from: serverURLText) == nil {
                    Section {
                        Button("サーバーURLを設定する") { isShowingSettings = true }
                    } footer: {
                        Text("ログインする前に，接続先のサーバーURLを設定してください．")
                    }
                }

                Section {
                    TextField("メールアドレス", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("パスワード", text: $password)
                        .textContentType(mode == .login ? .password : .newPassword)
                    if mode == .register {
                        SecureField("パスワード(確認)", text: $passwordConfirmation)
                            .textContentType(.newPassword)
                    }
                } footer: {
                    if mode == .register {
                        Text("パスワードは\(Self.minimumPasswordLength)文字以上にしてください．")
                    }
                }

                Section {
                    Button(action: submit) {
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(mode.rawValue)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(isSubmitting || email.isEmpty || password.isEmpty)
                } footer: {
                    if let errorMessage {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("EchoMind")
            .toolbar {
                Button("サーバー設定", systemImage: "gearshape") { isShowingSettings = true }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView()
            }
            .onChange(of: mode) { errorMessage = nil }
        }
    }

    /// 入力内容を検証し，ログインまたはアカウント登録を実行する．
    private func submit() {
        if let validationError = validate() {
            errorMessage = validationError
            return
        }

        errorMessage = nil
        isSubmitting = true
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            defer { isSubmitting = false }
            do {
                switch mode {
                case .login:
                    try await authSession.login(email: trimmedEmail, password: password)
                case .register:
                    try await authSession.register(email: trimmedEmail, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// 送信前に入力内容を検証する．
    /// - Returns: 問題がある場合はエラーメッセージ．問題がなければnil．
    private func validate() -> String? {
        guard mode == .register else { return nil }
        if password.count < Self.minimumPasswordLength {
            return "パスワードは\(Self.minimumPasswordLength)文字以上にしてください．"
        }
        if password != passwordConfirmation {
            return "確認用のパスワードが一致しません．"
        }
        return nil
    }
}

#Preview {
    LoginView()
        .environment(AuthSession())
}
