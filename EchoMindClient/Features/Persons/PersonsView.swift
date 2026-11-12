import SwiftUI

/// 人物タブの画面．人物の一覧と名前の設定，人物ごとの会話一覧への移動を行う．
///
/// 名前は各行の鉛筆のボタン，左スワイプ，長押しのいずれからも設定できる．
struct PersonsView: View {
    @State private var persons: [Person] = []
    @State private var hasLoaded = false
    @State private var errorMessage: String?
    @State private var editingTarget: PersonNameTarget?

    var body: some View {
        List {
            ForEach(persons) { person in
                NavigationLink(value: person) {
                    HStack {
                        PersonRow(person: person)
                        Spacer()
                        Button("名前を設定", systemImage: "pencil") { startEditing(person) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("名前を設定", systemImage: "pencil") { startEditing(person) }
                        .tint(.accentColor)
                }
                .contextMenu {
                    Button("名前を設定", systemImage: "pencil") { startEditing(person) }
                }
            }
            if let errorMessage {
                LoadErrorRow(message: errorMessage) {
                    Task { await load() }
                }
            }
        }
        .overlay {
            if !hasLoaded {
                ProgressView()
            } else if persons.isEmpty && errorMessage == nil {
                ContentUnavailableView(
                    "人物がいません",
                    systemImage: "person.2",
                    description: Text("会話が処理されると，話者がここに表示されます．")
                )
            }
        }
        .navigationTitle("人物")
        .navigationDestination(for: Person.self) { person in
            ConversationListView(personId: person.personId, title: person.displayName)
        }
        .task {
            if !hasLoaded {
                await load()
            }
        }
        .refreshable { await load() }
        .personNameEditor(target: $editingTarget) { updated in
            if let index = persons.firstIndex(where: { $0.personId == updated.personId }) {
                persons[index] = updated
            }
        }
    }

    /// 名前の入力を開始する．
    /// - Parameter person: 名前を設定する人物
    private func startEditing(_ person: Person) {
        editingTarget = PersonNameTarget(personId: person.personId, currentName: person.name)
    }

    /// 人物一覧を読み込む．
    private func load() async {
        errorMessage = nil
        defer { hasLoaded = true }
        do {
            persons = try await BrowseAPI.persons()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// 人物一覧の1行．名前と発言数を表示する．
private struct PersonRow: View {
    let person: Person

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(person.displayName)
                .font(.headline)
                .foregroundStyle(person.name == nil ? .secondary : .primary)
            Text("発言 \(person.utteranceCount)件")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    NavigationStack {
        PersonsView()
    }
}
