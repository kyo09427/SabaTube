-- ============================================================
-- 通知機能マイグレーション
-- 実行日: 2026-03-28
-- 概要: notifications テーブル、RLSポリシー、
--       新規動画投稿時に購読者へ通知を生成するDBトリガーを追加
-- ============================================================

-- ------------------------------------------------------------
-- 1. notifications テーブル
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notifications (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type       TEXT        NOT NULL DEFAULT 'new_video',
  title      TEXT        NOT NULL,
  body       TEXT        NOT NULL,
  data       JSONB,                -- { "video_id", "channel_id", "channel_name" }
  is_read    BOOLEAN     NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- 2. インデックス
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS notifications_user_id_idx
  ON notifications (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS notifications_unread_idx
  ON notifications (user_id)
  WHERE is_read = FALSE;

-- ------------------------------------------------------------
-- 3. RLS（Row Level Security）
-- ------------------------------------------------------------
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- 本人のみ自分の通知を閲覧できる
CREATE POLICY "notifications_select_own"
  ON notifications FOR SELECT
  USING (auth.uid() = user_id);

-- 本人のみ自分の通知を既読に更新できる
CREATE POLICY "notifications_update_own"
  ON notifications FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- INSERT は SECURITY DEFINER のトリガー関数のみ（直接INSERTは不可）
-- ※ サービスロール経由のINSERTはRLSをバイパスするため追加ポリシー不要

-- ------------------------------------------------------------
-- 4. トリガー関数: 新規動画投稿時に購読者へ通知を生成
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION notify_subscribers_on_new_video()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER  -- RLSをバイパスしてINSERTできるようにする
SET search_path = public
AS $$
BEGIN
  -- 投稿者チャンネルを登録している全ユーザーに通知を生成
  INSERT INTO notifications (user_id, type, title, body, data)
  SELECT
    s.subscriber_id,
    'new_video',
    p.username || 'さんが動画を投稿しました',
    COALESCE(NEW.title, '新しい動画'),
    jsonb_build_object(
      'video_id',     NEW.id,
      'channel_id',   NEW.user_id,
      'channel_name', p.username
    )
  FROM subscriptions s
  JOIN profiles p ON p.id = NEW.user_id
  WHERE s.channel_id = NEW.user_id;

  RETURN NEW;
END;
$$;

-- ------------------------------------------------------------
-- 5. トリガー: videos INSERT 後に発火
-- ------------------------------------------------------------
DROP TRIGGER IF EXISTS on_new_video_notify ON videos;

CREATE TRIGGER on_new_video_notify
  AFTER INSERT ON videos
  FOR EACH ROW
  EXECUTE FUNCTION notify_subscribers_on_new_video();
