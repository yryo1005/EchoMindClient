# order_006

## ユーザーの指示

> Step 0から実装してください
>
> 私がXCodeで確認する必要があれば指示してください

## 指示の解釈

- order_001で提示した実装ステップのうち，Step 0(プロジェクトの土台)を実装する．
  - Xcodeプロジェクトのビルド確認，フォルダ構成(App / Features / Services / Models / Config)の決定
  - Info.plistの設定: マイク使用許可の説明文，バックグラウンドモード(audio, processing)，BGTaskの識別子，ローカルネットワークへのHTTP接続許可
  - サーバーURL(Cloudflare Tunnel)を設定値として外出しし，アプリ内の設定画面から変更・疎通確認(`GET /health`)できるようにする
  - 対象プラットフォームをiPhone(iOS)に絞る(テンプレートはmacOS/visionOSも含むマルチプラットフォーム設定だったが，AVAudioSession等のiOS専用APIを使うため)
- Xcodeのコマンドライン(xcodebuild)とシミュレーターでビルド・起動を確認し，GUIでの確認が必要な事項(署名・実機・Bundle Identifier等)はユーザーに指示する．
- 作業後に`document.md`と`.reports/report_001.md`を作成する．
