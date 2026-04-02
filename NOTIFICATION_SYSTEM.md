# 通知システム 詳細仕様書

> 対象: SabaTube  
> 更新: 2026-04-03  
> 担当: 引継ぎ・不具合対応用

---

## 目次

1. [システム全体像](#1-システム全体像)
2. [データベース設計](#2-データベース設計)
3. [通知が届くまでの流れ](#3-通知が届くまでの流れ)
4. [FCM セットアップ](#4-fcm-セットアップ)
5. [NotificationService 詳細](#5-notificationservice-詳細)
6. [クロスプラットフォーム強制ログアウト](#6-クロスプラットフォーム強制ログアウト)
7. [UI コンポーネント](#7-ui-コンポーネント)
8. [SharedPreferences キー一覧](#8-sharedpreferences-キー一覧)
9. [新環境セットアップチェックリスト](#9-新環境セットアップチェックリスト)
10. [トラブルシューティング](#10-トラブルシューティング)

---

## 1. システム全体像

通知システムは **2 層構造** になっている。

```
┌─────────────────────────────────────────────────────────┐
│  Layer 1: アプリ内通知                                    │
│  Supabase DB (notifications テーブル) + Realtime          │
│  → 未読バッジ・通知一覧画面                                │
└─────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────┐
│  Layer 2: プッシュ通知                                    │
│  Firebase Cloud Messaging (FCM)                          │
│  → OS ネイティブ通知（ロック画面・通知センター）            │
└─────────────────────────────────────────────────────────┘
```

### 使用サービス

| サービス | 用途 |
|---------|------|
| Supabase Database | notifications テーブル・プロフィールトークン保存 |
| Supabase Realtime | 新着通知のリアルタイム受信・強制ログアウト検知 |
| Supabase DB トリガー | 動画投稿時に通知レコードを自動生成 |
| Firebase FCM | Android/Web へのプッシュ通知配信 |
| SharedPreferences | FCM トークン登録済みフラグの永続化 |

### Firebase プロジェクト情報

| 項目 | 値 |
|-----|---|
| プロジェクト ID | `sabatube` |
| Sender ID | `54119387843` |
| Web App ID | `1:54119387843:web:a1fcfeec245732dae94876` |
| Android App ID | `1:54119387843:android:36134ea59076e0bfe94876` |
| VAPID 公開鍵 (Web FCM) | `BEexX4VY1EtJqthnxOe56_RAHTkiwzsQkvDnbnrpxKV0tReZcZYOEqf-STo2O6nXUtuSPEwqqBSC3UTDBCkbXU0` |

---

## 2. データベース設計

### notifications テーブル

```sql
CREATE TABLE notifications (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type       TEXT        NOT NULL DEFAULT 'new_video',
  title      TEXT        NOT NULL,
  body       TEXT        NOT NULL,
  data       JSONB,      -- { "video_id", "channel_id", "channel_name" }
  is_read    BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**インデックス**
- `(user_id, created_at DESC)` — 通知一覧取得用
- `(user_id) WHERE is_read = FALSE` — 未読数カウント用（部分インデックス）

**RLS ポリシー**
- SELECT: `auth.uid() = user_id`（本人のみ閲覧可）
- UPDATE: `auth.uid() = user_id`（本人のみ既読更新可）
- INSERT: トリガー関数（SECURITY DEFINER）のみ。直接 INSERT 不可。

### profiles テーブル（FCM トークン関連カラム）

| カラム | 型 | 説明 |
|-------|---|-----|
| `fcm_token` | TEXT, nullable | Android の FCM デバイストークン |
| `web_fcm_token` | TEXT, nullable | Web の FCM デバイストークン |

**設計ルール**: 同一ユーザーの両カラムが同時に設定されることはない。  
`registerFcmToken()` は必ず自分のカラムを SET し、相手のカラムを NULL にする。

### DB トリガー: 動画投稿 → 通知自動生成

```
videos テーブルに INSERT
  → on_new_video_notify トリガー発火（AFTER INSERT FOR EACH ROW）
  → notify_subscribers_on_new_video() 関数実行（SECURITY DEFINER）
  → 投稿者を登録している全ユーザーの notifications に INSERT
```

生成される通知レコード例:
```json
{
  "user_id": "<購読者のUUID>",
  "type": "new_video",
  "title": "さばさんが動画を投稿しました",
  "body": "【新作】○○を食べてみた",
  "data": {
    "video_id": "xxx",
    "channel_id": "yyy",
    "channel_name": "さば"
  }
}
```

---

## 3. 通知が届くまでの流れ

### 3-1. フォアグラウンド時（アプリが開いている）

```
動画投稿 (videos INSERT)
  ↓
DB トリガー → notifications INSERT
  ↓
Supabase Realtime (_realtimeChannel が INSERT イベントを受信)
  ↓
unreadCount.value += 1
  ↓
home_screen.dart の ValueListenableBuilder が再描画
  ↓
AppBar の通知ベルに赤バッジ表示
```

FCM メッセージも同時に届くが、`FirebaseMessaging.onMessage` で受信して  
`unreadCount.value += 1` する（Realtime と重複するため +2 になる可能性あり）。  
→ 実際の未読数は `refreshUnreadCount()` で DB から再取得して同期される。

> **NOTE**: フォアグラウンド時に FCM と Realtime の両方で unreadCount が加算される  
> 二重カウントの可能性がある。通知一覧を開くと `fetchNotifications()` が走るが、  
> unreadCount のリセットは `markAllAsRead()` か個別の `markAsRead()` が必要。

### 3-2. バックグラウンド時（Android）

```
動画投稿 → DB トリガー → notifications INSERT
  ↓
FCM サーバーがデバイスに PUSH 送信
  ↓
Android OS がネイティブ通知を表示（バナー・通知センター）
  ↓ アプリ復帰時
_firebaseMessagingBackgroundHandler は Isolate 分離のため
unreadCount 更新は不可
  ↓
initialize() → refreshUnreadCount() で DB から取得して同期
```

### 3-3. バックグラウンド時（Web）

```
動画投稿 → DB トリガー → notifications INSERT
  ↓
FCM サーバーがブラウザに PUSH 送信
  ↓
Service Worker (firebase-messaging-sw.js) が受信
  ↓
self.registration.showNotification() でブラウザ通知を表示
  ↓ ブラウザタブに戻った時
Realtime が未読数を同期（タブがアクティブなら）
```

### 3-4. アプリ終了時（Android）

FCM がバックグラウンドハンドラより低い優先度で通知を表示。  
アプリ再起動後に `refreshUnreadCount()` が走る。

---

## 4. FCM セットアップ

### Android 側

**設定ファイル**: `android/app/google-services.json`  
FlutterFire CLI で自動生成（`firebase_options.dart` も同様）。

**AndroidManifest.xml に必要な権限**:
```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```
(Android 13 以上で必須。Flutter の `requestPermission()` が OS ダイアログを出す)

**バックグラウンドハンドラ**:  
`notification_service.dart` のトップレベル関数 `_firebaseMessagingBackgroundHandler`。  
`@pragma('vm:entry-point')` アノテーションが必須（tree-shaking 防止）。

### Web 側

**Service Worker**: `web/firebase-messaging-sw.js`  
ブラウザがバックグラウンドでも通知を受け取るために必須。  
`index.html` と同じオリジンに配置されている必要がある。

```js
// web/firebase-messaging-sw.js
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

firebase.initializeApp({ /* firebase_options.dart の web と同じ設定 */ });
const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  self.registration.showNotification(title, { body, icon });
});
```

> **重要**: `firebase-messaging-sw.js` の Firebase 設定値は `firebase_options.dart` の  
> `web` 設定と **完全に一致**させること。不一致だとトークン取得が失敗する。

**VAPID 鍵**:  
Web FCM でトークンを取得するために必要な公開鍵。  
Firebase Console > Project Settings > Cloud Messaging > Web configuration > 鍵ペア で確認・再生成できる。  
`notification_service.dart` の `_kWebVapidKey` 定数に設定。

**ブラウザ制限**:  
- Safari (iOS) は Web Push 非対応（iOS 16.4 以降の PWA インストール時のみ対応）
- Chrome / Edge / Firefox で動作確認済み

---

## 5. NotificationService 詳細

**場所**: `lib/services/notification_service.dart`  
**パターン**: シングルトン（`NotificationService.instance`）

### 初期化フロー

```
ログイン成功
  ↓ (main.dart の AuthWrapper が addPostFrameCallback で呼ぶ)
NotificationService.instance.initialize()
  ↓
_isInitialized チェック（多重呼び出し防止）
  ↓
_isDisplacedByAnotherPlatform() ← タスクキル後の強制ログアウト確認
  ↓ false の場合のみ続行
refreshUnreadCount()     ← DB から未読数取得
_subscribeRealtime()     ← notifications テーブルの INSERT を購読
_subscribeProfileChanges() ← profiles テーブルの UPDATE を購読（強制ログアウト検知）
_initFcm()               ← FCM 権限要求・トークン取得・リスナー登録
```

### ログアウトフロー

**呼び出し順序が重要**。必ず以下の順番で呼ぶこと:

```dart
await NotificationService.instance.dispose();      // 1. Realtime 購読解除 + フラグリセット
await NotificationService.instance.clearFcmToken(); // 2. DB からトークン削除 + SharedPreferences リセット
await SupabaseService.instance.signOut();           // 3. Supabase セッション終了
```

`dispose()` を先に呼ぶ理由: `clearFcmToken()` が DB を更新すると Realtime が発火し、  
`_subscribeProfileChanges()` の誤検知が起きる可能性があるため。  
`dispose()` で先に購読を解除することで防ぐ。

### フィールド一覧

| フィールド | 型 | 説明 |
|-----------|---|-----|
| `unreadCount` | `ValueNotifier<int>` | 未読通知数。UI は `ValueListenableBuilder` でリッスン |
| `forcedLogout` | `ValueNotifier<bool>` | 他プラットフォームログイン検知フラグ。main.dart がリッスン |
| `_realtimeChannel` | `RealtimeChannel?` | notifications テーブルの購読チャンネル |
| `_profilesChannel` | `RealtimeChannel?` | profiles テーブルの購読チャンネル |
| `_isInitialized` | `bool` | 多重初期化防止フラグ |
| `_isFcmInitialized` | `bool` | FCM リスナー多重登録防止フラグ |
| `_hadToken` | `bool` | インメモリのトークン登録済みフラグ（Realtime コールバック用） |
| `_isDisposing` | `bool` | ログアウト処理中フラグ（Realtime 誤検知防止） |

### メソッド一覧

| メソッド | 呼び出し元 | 説明 |
|---------|----------|-----|
| `initialize()` | main.dart (AuthWrapper) | ログイン後の初期化 |
| `dispose()` | main.dart (ログアウト時) | 購読解除・フラグリセット |
| `refreshUnreadCount()` | initialize() / 手動 | DB から未読数を再取得 |
| `fetchNotifications()` | NotificationsScreen | 最新50件取得 |
| `markAsRead(id)` | NotificationsScreen | 指定通知を既読 |
| `markAllAsRead()` | NotificationsScreen | 全通知を既読 |
| `registerFcmToken(token)` | _initFcm() / refreshFcmToken() | トークンを DB に保存 |
| `clearFcmToken()` | ログアウト時 / トグル OFF | DB からトークン削除 |
| `refreshFcmToken()` | my_page_screen.dart | トグル ON 時にトークン再取得 |

### Realtime チャンネル

**チャンネル 1: `notifications:{userId}`**  
- テーブル: `notifications`
- イベント: INSERT のみ
- フィルタ: `user_id = {userId}`
- 目的: 自分宛ての新着通知 → `unreadCount += 1`

**チャンネル 2: `profile_session:{userId}`**  
- テーブル: `profiles`
- イベント: UPDATE のみ
- フィルタ: `id = {userId}`
- 目的: 強制ログアウト検知（自分の FCM トークンが消されたことを検知）

---

## 6. クロスプラットフォーム強制ログアウト

詳細は `CROSS_PLATFORM_LOGOUT.md` を参照。ここでは概要のみ記載。

### 仕組み

同一アカウントの Android/Web 同時ログインを禁止する。  
後からログインした側が「勝者」となり、先のセッションは強制ログアウトされる。

**2 つの検知経路**:

| 経路 | タイミング | 使用技術 |
|-----|----------|---------|
| Realtime 検知 | 両プラットフォームが同時起動中 | Supabase Realtime |
| 起動時検知 | タスクキルから復帰した時 | SharedPreferences + DB クエリ |

### 起動時検知の判定ロジック

```
SharedPreferences had_fcm_token == true  (以前トークンを登録していた)
  AND
DB の自分のトークンカラム == null         (タスクキル中に消された)
  ↓
強制ログアウト
```

---

## 7. UI コンポーネント

### 通知ベルアイコン（HomeScreen AppBar）

**場所**: `lib/screens/home/home_screen.dart`

```dart
ValueListenableBuilder<int>(
  valueListenable: NotificationService.instance.unreadCount,
  builder: (context, count, _) {
    return Stack(
      children: [
        IconButton(
          icon: Icon(Icons.notifications_outlined),
          onPressed: () => Navigator.push(_, NotificationsScreen()),
        ),
        if (count > 0)
          Positioned(top: 12, right: 12, child: /* 赤ドット */)
      ],
    );
  },
)
```

`unreadCount` が変化するたびに自動再描画される。

### 通知一覧画面（NotificationsScreen）

**場所**: `lib/screens/notifications/notifications_screen.dart`

- `initState()` で `fetchNotifications()` を実行
- 未読通知: 青系背景 + 右端に赤ドット + 太字テキスト
- タップ: `markAsRead()` → `channelId` があればチャンネル画面へ遷移
- 「すべて既読」ボタン: 未読通知が存在する場合のみ AppBar に表示
- pull-to-refresh: `_load()` で再フェッチ
- 表示件数: 最新 50 件（DB クエリ `LIMIT 50 ORDER BY created_at DESC`）

### 通知トグル（MyPageScreen）

**場所**: `lib/screens/profile/my_page_screen.dart`

- ON にする:
  1. `FirebaseMessaging.instance.requestPermission()` で OS 権限確認
  2. 権限あり → `NotificationService.instance.refreshFcmToken()` でトークン取得・DB 保存
  3. 権限なし → トグルを戻してエラー表示
- OFF にする:
  1. `NotificationService.instance.clearFcmToken()` でトークンを DB から削除
  2. SharedPreferences `had_fcm_token = false` もリセットされる

> **注意**: トグル OFF で `clearFcmToken()` が呼ばれると SharedPreferences の  
> `had_fcm_token` が false になる。つまり「意図的に通知 OFF にしてタスクキル」した  
> ユーザーは、再起動後に強制ログアウトされない（正しい挙動）。

### 強制ログアウトダイアログ（AuthWrapper）

**場所**: `lib/main.dart`

```
forcedLogout.value → true
  ↓ _onForcedLogout() が発火
AlertDialog:
  タイトル: 「別のデバイスでログイン」
  本文:   「[Android アプリ or ブラウザ] から同じアカウントでログインされました。
           このセッションを終了します。」
  ボタン: OK のみ（barrierDismissible: false で強制）
  ↓ OK 押下
dispose() → clearFcmToken() → signOut()
```

---

## 8. SharedPreferences キー一覧

| キー | 型 | セット場所 | リセット場所 | 用途 |
|-----|---|----------|------------|-----|
| `had_fcm_token` | bool | `registerFcmToken()` 成功時 | `clearFcmToken()` 実行時 | タスクキル後の強制ログアウト判定 |
| `notifications_enabled` | bool | MyPageScreen トグル操作時 | MyPageScreen トグル操作時 | 通知の有効/無効設定の表示状態 |

---

## 9. 新環境セットアップチェックリスト

### Firebase

- [ ] Firebase Console でプロジェクト `sabatube` にアクセスできる
- [ ] `android/app/google-services.json` が最新か確認
- [ ] `lib/firebase_options.dart` が FlutterFire CLI で生成されているか確認
- [ ] Cloud Messaging API が有効になっているか確認
  - Firebase Console > Project Settings > Cloud Messaging > Cloud Messaging API (V1)
- [ ] VAPID 鍵が `_kWebVapidKey` と Firebase Console の値と一致しているか確認
- [ ] `web/firebase-messaging-sw.js` の Firebase 設定が `firebase_options.dart` の `web` と一致しているか

### Supabase

- [ ] `notifications` テーブルが存在するか
  - `notifications_migration.sql` を実行済みか確認
- [ ] `profiles` テーブルに `fcm_token`, `web_fcm_token` カラムが存在するか
- [ ] DB トリガー `on_new_video_notify` が有効か
  - `SELECT * FROM pg_trigger WHERE tgname = 'on_new_video_notify';`
- [ ] `profiles` テーブルが Supabase Realtime に登録されているか
  - Dashboard > Database > Replication > supabase_realtime publication
  - SQL: `SELECT tablename FROM pg_publication_tables WHERE pubname = 'supabase_realtime';`
  - 含まれていない場合: `ALTER PUBLICATION supabase_realtime ADD TABLE profiles;`
- [ ] `notifications` テーブルが Realtime に登録されているか（同上）

### Android ビルド

- [ ] `android/app/src/main/AndroidManifest.xml` に `POST_NOTIFICATIONS` 権限あるか
- [ ] `minSdkVersion` >= 21 か（FCM 要件）

### Web デプロイ

- [ ] `firebase-messaging-sw.js` がドメインのルートに配置されるか
  - Flutter Web ビルドでは `web/` フォルダのファイルがルートに配置される
- [ ] HTTPS 配信か（Service Worker は HTTPS 必須）

---

## 10. トラブルシューティング

### プッシュ通知が届かない

**共通**
- [ ] profiles テーブルにユーザーの `fcm_token` / `web_fcm_token` が保存されているか確認
  ```sql
  SELECT id, fcm_token, web_fcm_token FROM profiles WHERE id = '<user_id>';
  ```
- [ ] FCM サーバーキーが有効か（Firebase Console > Project Settings > Cloud Messaging）
- [ ] DB トリガーが正常に動作しているか
  ```sql
  SELECT * FROM notifications ORDER BY created_at DESC LIMIT 5;
  ```

**Android のみ**
- [ ] OS の通知権限が許可されているか（設定 > アプリ > SabaTube > 通知）
- [ ] `google-services.json` が `android/app/` に配置されているか
- [ ] バックグラウンドハンドラに `@pragma('vm:entry-point')` があるか
- [ ] デバッグビルドとリリースビルドで挙動が異なる場合は ProGuard の設定を確認

**Web のみ**
- [ ] ブラウザの通知権限を許可しているか（アドレスバー左の鍵アイコン）
- [ ] Service Worker が登録されているか
  - Chrome DevTools > Application > Service Workers
- [ ] `firebase-messaging-sw.js` の Firebase 設定が正しいか
- [ ] VAPID 鍵が一致しているか（Console と `_kWebVapidKey` 定数）
- [ ] HTTPS か（localhost は例外として HTTP 可）
- [ ] Safari では Web Push 非対応（PWA インストール + iOS 16.4+ の場合は対応）

### アプリ内の未読バッジが更新されない

- [ ] `notifications` テーブルが Supabase Realtime に登録されているか
- [ ] Supabase の WebSocket 接続が切れていないか（長時間放置後に起きやすい）
  - アプリの再起動で `initialize()` が呼ばれ `refreshUnreadCount()` が走る
- [ ] `_realtimeChannel` のチャンネル名が `notifications:{userId}` になっているか

### 強制ログアウトが発生しない（タスクキル後）

- [ ] `profiles` テーブルが Realtime に登録されているか（上記チェック）
- [ ] SharedPreferences の `had_fcm_token` が `true` になっているか
  - トークン登録が失敗していると `false` のまま
  - ログに `✅ FCMトークンを登録しました` が出ているか確認

### 意図せず強制ログアウトされる

- [ ] SharedPreferences の `had_fcm_token` が `true` のまま残っていないか
  - 原因: `clearFcmToken()` の失敗（ネットワークエラー等）
  - 対処: Supabase Console で直接トークンを null に更新
    ```sql
    UPDATE profiles
    SET fcm_token = NULL, web_fcm_token = NULL
    WHERE id = '<user_id>';
    ```
  - その後、アプリを再起動してログインし直す

### 通知トグル OFF が効かない

- [ ] `clearFcmToken()` が呼ばれているか（ログで `❌` が出ていないか）
- [ ] `had_fcm_token` のリセットに失敗していないか
- [ ] DB の更新が成功しているか（Supabase Console で確認）
- [ ] RLS ポリシーで `profiles` への UPDATE が許可されているか

### ログアウト後も通知が届く

- [ ] `clearFcmToken()` がログアウト前に正常に呼ばれているか
- [ ] ログアウトの順序確認: `dispose()` → `clearFcmToken()` → `signOut()`
  - `signOut()` を先に呼ぶと `currentUser` が null になり `clearFcmToken()` が空振りする

---

## 参考: 関連ファイル一覧

| ファイル | 役割 |
|---------|-----|
| `lib/services/notification_service.dart` | 通知全体の中核サービス |
| `lib/models/notification_model.dart` | 通知データモデル |
| `lib/main.dart` (`AuthWrapper`) | 強制ログアウトダイアログ・初期化呼び出し |
| `lib/screens/notifications/notifications_screen.dart` | 通知一覧画面 |
| `lib/screens/home/home_screen.dart` | 未読バッジ付き通知ベルアイコン |
| `lib/screens/profile/my_page_screen.dart` | 通知 ON/OFF トグル |
| `lib/firebase_options.dart` | Firebase 設定（FlutterFire CLI 生成） |
| `web/firebase-messaging-sw.js` | Web バックグラウンド通知 Service Worker |
| `web/index.html` | PWA エントリーポイント |
| `notifications_migration.sql` | notifications テーブル + トリガー定義 |
| `CROSS_PLATFORM_LOGOUT.md` | 強制ログアウト機能の詳細仕様 |
