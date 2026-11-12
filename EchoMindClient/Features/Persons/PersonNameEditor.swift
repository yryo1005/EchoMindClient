import SwiftUI

/// 名前を設定する対象の人物．
struct PersonNameTarget: Identifiable {
    let personId: String
    /// 現在の名前(未設定の場合はnil)．入力欄の初期値に用いる．
    let currentName: String?

    var id: String { personId }
}

/// 人物の名前を入力してサーバーに保存するダイアログを表示する修飾子．
///
/// 人物タブと会話の詳細画面で共用する．保存に成功すると`onSaved`に更新後の人物を渡す．
private struct PersonNameEditor: ViewModifier {
    @Binding var target: PersonNameTarget?
    let onSaved: (Person) -> Void

    @State private var nameDraft = ""
    @State private var saveErrorMessage: String?

    func body(content: Content) -> some View {
        content
            .alert("名前を設定", isPresented: isEditing, presenting: target) { target in
                TextField("名前", text: $nameDraft)
                Button("保存") {
                    Task { await save(target) }
                }
                Button("キャンセル", role: .cancel) {}
            } message: { _ in
                Text("この人物のすべての発言にこの名前が表示されます．")
            }
            .alert(
                "名前を保存できませんでした",
                isPresented: Binding(get: { saveErrorMessage != nil }, set: { if !$0 { saveErrorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage ?? "")
            }
            .onChange(of: target?.personId) {
                nameDraft = target?.currentName ?? ""
            }
    }

    /// 名前の入力欄を表示しているかどうか．
    private var isEditing: Binding<Bool> {
        Binding(get: { target != nil }, set: { if !$0 { target = nil } })
    }

    /// 入力された名前をサーバーに保存する．
    /// - Parameter target: 名前を設定する人物
    private func save(_ target: PersonNameTarget) async {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            saveErrorMessage = "名前を入力してください．"
            return
        }
        do {
            onSaved(try await BrowseAPI.updatePersonName(personId: target.personId, name: name))
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

extension View {
    /// 人物の名前を設定するダイアログを表示する．`target`に人物を設定すると表示される．
    /// - Parameters:
    ///   - target: 名前を設定する人物
    ///   - onSaved: 保存に成功した際の処理(引数は更新後の人物)
    /// - Returns: ダイアログを付与したビュー
    func personNameEditor(target: Binding<PersonNameTarget?>, onSaved: @escaping (Person) -> Void) -> some View {
        modifier(PersonNameEditor(target: target, onSaved: onSaved))
    }
}
