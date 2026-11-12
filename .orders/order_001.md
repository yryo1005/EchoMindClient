# order_001

## ユーザーの指示

> https://github.com/yryo1005/EchoMindServer.git
> ↑のリポジトリの内容を確認してください
>
> このリポジトリではIOSのアプリ部分（クライアント）を実装します
> 実装ステップを考えてください

## 指示の解釈

- EchoMindServer(FastAPI)の仕様書・API実装を読み，iOSクライアントが満たすべき要件と利用するAPIを整理する．
- 本orderではコードの実装は行わず，iOSクライアントの実装ステップ(計画)を提示するまでを対象とする．
- 計画はチャット欄で提示する(ファイル化・実装は次のorder以降でユーザーの指示を受けて行う)．

## 確認したサーバー側の主な前提

- 認証: `POST /api/auth/register`，`POST /api/auth/login`(JWT，有効期限7日)，`GET /api/auth/me`
- アップロード: `POST /api/upload`(multipart `file`)．サーバーは受信時刻(`received_at`)を録音開始時刻として扱っている．
- QA: `POST /api/chat` `{"query": ...}` → `{"answer", "references"}`
- 閲覧: `GET /api/persons`，`PUT /api/persons/{id}/name`，`GET /api/conversations`，`GET /api/conversations/{id}`，`GET /api/audio/{utterance_id}`
