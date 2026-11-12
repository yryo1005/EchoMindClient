# EchoMindClient

ライフログ音声解析・QAシステム「EchoMind」のiPhoneアプリ(クライアント)の実装である．サーバー側の実装と仕様は[EchoMindServer](https://github.com/yryo1005/EchoMindServer)の`仕様書.md`，`document.md`，`programs/server/README.md`に記載されている．本アプリは，日常の音声を常時録音してWi-Fi接続中かつ充電中にサーバーへ送信する機能と，過去の会話への質問(QA)・会話の閲覧・話者名の設定を行う機能を持つ．

## 実装の進捗

実装は以下のステップで進める．

| Step | 内容 | 状態 |
| :---: | :--- | :---: |
| 0 | プロジェクトの土台(フォルダ構成，Info.plist，サーバーURLの設定と疎通確認) | 完了 |
| 1 | APIクライアントと認証(登録・ログイン，Keychainへのトークン保存) | 完了 |
| 2 | QAチャット画面 | 完了 |
| 3 | 会話の閲覧，発言音声の再生，話者名の設定 | 完了 |
| 4 | 常時録音(1時間ごとのファイル分割，中断からの復帰，Bluetooth機器の接続中も本体のマイクで継続) | 完了 |
| 5 | 条件付き自動アップロード，手動での送信，処理完了後の削除 | 完了 |
| 6 | 状態表示・設定画面の拡充(状態の一覧，自動送信の条件の設定，録音タブのバッジ，人物名の編集の導線) | 完了(人物名の編集の導線は実機での確認待ち) |
| 7 | 実機での長時間検証(検証用の録音・送信のログを実装済み) | 準備中 |

## ディレクトリ構成

- `EchoMindClient/`: アプリのソースコード．Xcodeのフォルダ同期により，このディレクトリ以下に置いたファイルは自動的にビルド対象となる(プロジェクトファイルへの登録は不要)．
  - `App/MyApp.swift`: アプリのエントリポイント．共有の`AuthSession`とSwiftDataのコンテナ(`AppDataStore`)を設定する．起動時に記録されていない録音ファイルを記録し，録音が有効であれば再開する．前面に戻った時にも録音を再開する．起動時・前面に戻った時に録音ファイルの送信を開始し，バックグラウンドに移る際にはバックグラウンドでの送信(`BGProcessingTask`)を予約する．
  - `App/RootView.swift`: ルート画面．未ログインの場合はログイン画面を，ログイン済みの場合は質問・会話・人物・録音・設定の5つのタブを表示する．録音タブには対処が必要な項目(録音が有効なのに止まっている，送信を中止した録音)の数をバッジで表示する．
  - `Config/AppConfig.swift`: アプリ全体の設定値．サーバーURLはUserDefaultsに保存し，入力値の検証と正規化を行う．
  - `Models/AuthModels.swift`: 認証APIのリクエスト・レスポンスの型(`Credentials`，`TokenResponse`，`User`)．
  - `Models/BrowseModels.swift`: 閲覧APIの型(`Person`，`ConversationSummary`，`ConversationDetail`，`Utterance`)．名前が未設定の人物は「名前未設定 (人物IDの先頭8文字)」と表示する．
  - `Models/RecordingFile.swift`: 端末内に保存した録音ファイルの記録(SwiftData)．ID(`client_file_id`)，ファイル名，録音開始・終了時刻，サイズと，送信の状態(送信待ち，サーバーで処理中，送信を中止)，アップロード記録のID，失敗の回数，次に試行する日時を持つ．
  - `Models/UploadModels.swift`: 送信APIのレスポンスの型(`UploadResponse`，`UploadStatusResponse`)．
  - `Models/ChatModels.swift`: QA APIのリクエスト・レスポンスの型(`ChatRequest`，`ChatResponse`)と，端末内に保存するチャット履歴のSwiftDataモデル(`ChatMessage`)．履歴はユーザーIDでアカウントごとに分ける．
  - `Services/APIClient.swift`: EchoMindServerのAPIクライアント．Bearerトークンの付与，JSONのスネークケースとキャメルケースの変換，FastAPIのエラーメッセージ(`detail`)の取り出し，サーバーの日時(UTC，ISO8601)の解釈を行う．認証が必要なAPIで401が返った場合は`onUnauthorized`を呼ぶ．
  - `Services/KeychainStore.swift`: Keychainへの文字列の保存・取得・削除．初回のロック解除後は画面ロック中でも読み出せる設定とする．
  - `Services/AuthSession.swift`: ログイン状態の管理(登録，ログイン，ログアウト，ユーザー情報の取得)．アクセストークンがKeychainにあればサーバーに問い合わせずにログイン済みとして扱い，401を受けた場合は自動的にログアウトする．ユーザー情報はUserDefaultsにも保存し，オフラインで起動した場合もアカウントを識別できるようにする．アプリでは共有インスタンス`AuthSession.shared`を使用する．
  - `Services/ServerHealth.swift`: サーバーの疎通確認(`GET /health`)．
  - `Services/AppDataStore.swift`: アプリ全体で共有するSwiftDataのコンテナ(`ChatMessage`，`RecordingFile`)．
  - `Services/AudioSessionManager.swift`: `AVAudioSession`の設定．録音と再生を両立させるため`.playAndRecord`(`.mixWithOthers`，`.defaultToSpeaker`，`.allowBluetoothA2DP`)に統一する．入力をiPhone本体のマイクに固定し，現在の入力が本体のマイクかを判定する．
  - `Services/AudioRecorder.swift`: 常時録音の制御．`AVAudioEngine`のタップでマイクの音声を受け取り，中断(`.didBecomeInactive`，`.resumptionRecommendation`)，経路の変化，メディアサービスのリセットの後に録音を再開する．AirPods等のBluetooth機器やイヤホンの接続中も本体のマイクで録音を続け，本体のマイクを使えない間のみ`AVAudioEngine`を動かしたまま書き込みを一時停止する．手動での送信のために書き込み中の録音ファイルを区切る．再開できない場合はローカル通知で知らせる．録音の有効・無効はUserDefaultsに保存する．
  - `Services/RecordingFileWriter.swift`: マイクの音声を16kHzモノラル，32kbpsのAAC(ADTS)に変換して書き込み，1時間ごとにファイルを切り替える．録音が止まる際は必ずファイルを区切る(ファイルの途中に録音の空白を含めないため)．
  - `Services/RecordingStorage.swift`: 録音ファイルの保存先(Application Support/Recordings，バックアップ対象外)とファイル名の規則(`rec_<開始時刻UTC>_<ID>.aac`)，保存先の空き容量の取得．
  - `Services/LocalNotifier.swift`: 録音が停止したことを知らせるローカル通知．
  - `Services/EventLog.swift`: 録音と送信の経過のログ．録音の開始・停止・中断，録音ファイルの区切り(区間，サイズ，バッテリー残量)，送信の結果，Wi-Fi・充電の変化，アプリの起動と前面・バックグラウンドの切り替えを，JSON Lines形式で`Application Support/Logs/events.jsonl`に追記する．14日より古い記録は起動時に削除する．
  - `Services/RecordingTimeline.swift`: ログの録音ファイルの区切りから，期間内の録音時間，録音の空白(5秒を超える隙間)とその間の出来事，バッテリー残量の推移を集計する．
  - `Services/UploadManager.swift`: 録音ファイルの送信．Wi-Fiに接続し，かつ充電中の場合に自動で，`sendNow()`では条件に関わらず送信する．録音開始時刻の古い順に1件ずつ送信し，処理状況をポーリングして`safe_to_delete_client_copy`が`true`になったファイルを削除する．`failed`は待ち時間を倍にしながら5回まで再送し，404と1時間を超える処理中は送り直す．通信の失敗は失敗の回数に数えない．ログアウトの前に未送信の録音をすべて削除する処理(`discardAllRecordings()`)も持つ．自動送信の条件(Wi-Fi接続時のみ，充電中のみ)の設定と，最後に送信が完了した日時をUserDefaultsに保存する．
  - `Services/BrowseAPI.swift`: 会話一覧(20件ずつ)・会話詳細・人物一覧・名前の設定・発言音声の取得．質問の参照日時を含む会話を，会話一覧を新しい順にたどって探す処理(`conversation(containing:)`)を持つ．
  - `Services/AudioClipPlayer.swift`: 発言の音声を認証付きでダウンロードし，`AVAudioPlayer`で再生する．取得した音声は画面を開いている間メモリに保持する．
  - `Shared/DateLabels.swift`: 画面に表示する日時の書式(「11/7 9:23」，「11/7(土) 9:00〜9:30」等)．端末のタイムゾーンで表示する．
  - `Features/Chat/ChatController.swift`: 質問の送信(`POST /api/chat`，待ち時間120秒)，回答・エラーの履歴への保存，失敗した質問の再送，履歴の削除．
  - `Features/Chat/ChatView.swift`: 質問タブの画面．アカウントの履歴の表示，入力欄，回答待ちの表示，回答の根拠となった会話の日時(タップすると該当する会話を開く)，エラー時の再送ボタン．
  - `Features/Conversations/ConversationListView.swift`: 会話一覧(会話タブと人物ごとの会話一覧で共用)．末尾までスクロールすると続きを読み込み，引き下げで再読み込みする．
  - `Features/Conversations/ConversationDetailView.swift`: 会話の発言一覧と発言ごとの音声再生．質問の参照日時から開いた場合は該当する発言を強調表示する．話者名をタップするとその人物の名前を設定できる．
  - `Features/Conversations/ConversationLookupView.swift`: 質問の参照日時を含む会話を探して詳細を表示する．
  - `Features/Persons/PersonsView.swift`: 人物タブ．人物一覧，名前の設定(各行の鉛筆のボタン，左スワイプ，長押し)，人物ごとの会話一覧への移動．
  - `Features/Persons/PersonNameEditor.swift`: 人物の名前を入力してサーバーに保存するダイアログ(`personNameEditor`修飾子)．人物タブと会話の詳細画面で共用する．
  - `Features/Recording/RecordingView.swift`: 録音タブ．常時録音の切り替え，録音の状態と経過時間，送信の条件(Wi-Fi，充電)と状況，「今すぐ送信」ボタン，保存した録音ファイルの一覧(送信の状況，再生，手動での削除)．
  - `Features/Recording/RecordingStatusLabel.swift`: 常時録音の状態のラベル(録音中は経過時間を表示)．録音タブと設定画面で共用する．
  - `Features/Recording/UploadConditionRows.swift`: 自動送信の条件(Wi-Fi，充電)の現在の状態の行．条件から外した項目には「条件外」と添える．録音タブと設定画面で共用する．
  - `Features/Logs/EventLogView.swift`: ログの画面(設定画面から開く)．期間(24時間，3日，7日)ごとの録音の集計と録音の空白，種類で絞り込んだログの一覧を表示し，ログのファイルを書き出せる．
  - `Features/Auth/LoginView.swift`: ログイン・アカウント登録画面．サーバーURLが未設定の場合は設定画面への導線を表示する．
  - `Features/Settings/SettingsView.swift`: 設定画面．ログイン済みの場合は，状態の一覧(録音の状態，未送信の録音の件数と容量，最後の送信の完了，送信の状況，端末の空き容量，ログの画面への移動)，常時録音の切り替え，自動送信の条件の設定，アカウントの表示とログアウトを表示する．サーバーURLの入力と疎通確認，アプリのバージョンも表示する．未送信の録音があるか常時録音が有効な場合は，ログアウトの前に警告し，録音を停止してすべて送信するか，録音を削除してログアウトするかを選ばせる(アカウント間で録音が混ざらないようにするため)．
  - `Assets.xcassets/`: アプリのアセット．
- `EchoMindClient-Info.plist`: Xcodeが自動生成するInfo.plistに追加で統合する設定．バックグラウンドモード(`audio`，`processing`)，BGTaskの識別子(`<Bundle Identifier>.upload`)，ローカルネットワークへのHTTP接続の許可(`NSAllowsLocalNetworking`)を記述する．フォルダ同期の対象外に置くことで，リソースとして重複してコピーされることを防いでいる．
- `EchoMindClient.xcodeproj/project.xcproj`: Xcode 27のテキスト形式のプロジェクトファイル．対象はiPhone(`SUPPORTED_PLATFORMS = iphoneos iphonesimulator`，`TARGETED_DEVICE_FAMILY = 1`)，iOS 27.2以降である．マイク使用許可の説明文(`NSMicrophoneUsageDescription`)はビルド設定`INFOPLIST_KEY_NSMicrophoneUsageDescription`で指定する．
- `.orders/`: 作業指示の記録．
- `.reports/`: 作業レポート．`figures/`にレポートで参照する画像を置く．
- `.ai/`: AIエージェント・開発規約のサブモジュール群．

## プログラム間の依存関係

```text
MyApp ──> RootView ──┬─(未ログイン)─> LoginView ──┬─> AuthSession.login / register
                     │                             └─> SettingsView (シート)
                     └─(ログイン済み)─> タブ ──┬─> ChatView ──> ChatController ──> POST /api/chat
                                               │     ├─> SwiftData (ChatMessage: 端末内の履歴)
                                               │     └─(参照日時)─> ConversationLookupView ──> ConversationDetailView
                                               ├─> ConversationListView ──> ConversationDetailView ──┬─> AudioClipPlayer
                                               │                                                     └─(話者名のタップ)─> PersonNameEditor
                                               ├─> PersonsView ──┬─> PersonNameEditor ──> 名前の設定 (PUT /api/persons/{id}/name)
                                               │                 └─> ConversationListView (person_idで絞り込み)
                                               ├─> RecordingView ──┬─> AudioRecorder.setEnabled
                                               │                   └─> UploadManager.sendNow
                                               └─> SettingsView ──┬─> AuthSession.logout
                                                                  ├─(未送信の録音あり)─> AudioRecorder.setEnabled(false) ──> UploadManager.sendNow / discardAllRecordings
                                                                  └─> ServerHealth ──> GET /health

AudioRecorder ──┬─> AudioSessionManager (.playAndRecord)
                ├─> AVAudioEngine (タップ) ──> RecordingFileWriter ──> RecordingStorage (rec_*.aac)
                ├─(ファイルの区切り)─> SwiftData (RecordingFile) ──> UploadManager.recordingsDidChange
                ├─(経路の変化)─> AudioSessionManager.preferBuiltInMic / isBuiltInMicInUse ──> 書き込みの一時停止・再開
                └─(再開できない場合)─> LocalNotifier
AudioRecorder，UploadManager，MyApp ──> EventLog (events.jsonl) <── EventLogView ──> RecordingTimeline (集計)
UploadManager ──┬─> NWPathMonitor (Wi-Fi)，UIDevice (充電)，BGTaskScheduler
                ├─> APIClient.upload ──> POST /api/upload (multipart)
                ├─> APIClient.send ──> GET /api/upload/{id}/status
                └─(処理完了)─> 録音ファイルとRecordingFileの削除
BrowseAPI ──> APIClient (GET /api/conversations, /api/conversations/{id}, /api/persons, /api/audio/{id})
AuthSession ──> APIClient ──┬─> AppConfig (サーバーURL)
     │                      ├─> KeychainStore (アクセストークン)
     │                      └─> POST /api/auth/register, /api/auth/login, GET /api/auth/me
     └─> KeychainStore (トークンの保存・削除)
APIClient ──(認証APIで401)──> AuthSession.shared.logout()
```

## サーバーとの通信仕様

本アプリが利用するEchoMindServerのAPIは以下である．認証が必要なAPIは`Authorization: Bearer <JWT>`ヘッダを付与する．JWTの有効期限は7日である．サーバーが返す日時はUTCであり，画面には日本時間に変換して表示する．

| API | 用途 | 使用するStep |
| :--- | :--- | :---: |
| `GET /health` | 疎通確認 | 0 |
| `POST /api/auth/register`，`POST /api/auth/login`，`GET /api/auth/me` | アカウント登録(パスワードは8文字以上)，ログイン，ユーザー情報の取得 | 1 |
| `POST /api/chat` | 質問に対する回答と参照タイムスタンプの取得 | 2 |
| `GET /api/conversations`，`GET /api/conversations/{id}` | 会話一覧・会話詳細の取得 | 3 |
| `GET /api/persons`，`PUT /api/persons/{id}/name` | 人物一覧の取得，名前の設定 | 3 |
| `GET /api/audio/{utterance_id}` | 発言音声(AAC)の取得 | 3 |
| `POST /api/upload` | 録音ファイルの送信(`file`，`recorded_started_at`，`client_file_id`) | 5 |
| `GET /api/upload/{upload_record_id}/status` | 処理状況と削除可否(`safe_to_delete_client_copy`)の取得 | 5 |

## 外部モジュールとの依存関係

外部のSwiftパッケージは使用しておらず，Apple標準のフレームワーク(SwiftUI，SwiftData，Foundation，Security，Observation，AVFoundation，UserNotifications)のみに依存する．Step 5からNetwork，BackgroundTasks，UIKit(充電の状態の取得)も使用する．

## 開発環境のセットアップ

Xcode 27.2以降が必要である．実機で実行する場合は，iPhoneの「設定」→「プライバシーとセキュリティ」→「デベロッパモード」を有効にし，XcodeのSettings → AccountsにApple IDでサインインしておく必要がある．`EchoMindClient.xcodeproj`をXcodeで開き，Signing & CapabilitiesでTeamとBundle Identifierを設定する．Bundle Identifierは`com.yryo1005.EchoMindClient`である．実機に初めてインストールした際は，iPhoneの「設定」→「一般」→「VPNとデバイス管理」で開発元を信頼する必要がある．

## ビルドと実行の方法

Xcodeから実行する場合は，スキーム`EchoMindClient`と実行先(シミュレーターまたは実機)を選択して実行する．コマンドラインからシミュレーター向けにビルドする場合は以下を実行する．

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project EchoMindClient.xcodeproj -scheme EchoMindClient \
  -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
```

アプリを起動したら，ログイン画面右上の歯車ボタンから設定画面を開き，サーバーURL(例: `https://<サブドメイン>.<ドメイン>`)を入力して「接続を確認」で疎通を確認する．その後，ログイン画面でアカウントを登録またはログインする．同じLAN内のサーバーにHTTPで接続する場合は`http://<IPアドレス>:8000`を入力する(IPアドレスやローカルネットワークへのHTTP接続はApp Transport Securityの例外として許可している)．実機から接続する場合は`localhost`ではなくMacのIPアドレスを指定し，サーバーを`--host 0.0.0.0`で起動する．初回の接続時に表示されるローカルネットワークへのアクセスの許可を求めるダイアログでは「許可」を選ぶ．

## ログの取り出し

録音と送信のログは，アプリの「設定」→「録音と送信のログ」で確認でき，右上のボタンで書き出せる．iPhoneをMacに接続している場合は，次のコマンドでMacに取り出せる．

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun devicectl device copy from --device <UDID> --domain-type appDataContainer \
  --domain-identifier com.yryo1005.EchoMindClient \
  --source "Library/Application Support/Logs/events.jsonl" --destination events.jsonl
```

## 文書およびレポートの保存場所

- 作業指示: `.orders/order_{n:03}.md`
- 作業レポート: `.reports/report_{n:03}.md`(Step 0は`report_006.md`，Step 1は`report_007.md`，Step 2は`report_009.md`，Step 3は`report_010.md`，Step 4は`report_011.md`，Step 5とBluetooth・ログアウトの対応は`report_012.md`，Step 6は`report_013.md`，ログは`report_014.md`)．レポートで参照する画像は`.reports/figures/`に置く．

## 必要なAPIキーや設定ファイル

アプリにAPIキーは埋め込まない．サーバーURLはアプリの設定画面から入力してUserDefaultsに保存し，認証トークン(JWT)はKeychain(サービス名`EchoMind`，アカウント名`accessToken`)に保存する．KeychainはBundle Identifierごとに分かれるため，Bundle Identifierを変更した場合は再ログインが必要である．`tokens.json`はAIエージェント用であり，Git管理対象外である．

## Git管理上の注意事項

- `xcuserdata/`，`DerivedData/`，`build/`，`*.xcuserstate`はGit管理対象外とした．ただし，`EchoMindClient.xcodeproj/xcuserdata/`以下のファイルは初回コミットで既に追跡されているため，追跡を外す場合は`git rm --cached -r EchoMindClient.xcodeproj/xcuserdata`を実行する必要がある．
- `tokens.json`はGit管理対象外である．
