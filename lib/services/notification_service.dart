import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/notification_model.dart';
import 'supabase_service.dart';

/// アプリ内通知を管理するシングルトンサービス。
///
/// 責務:
///   - 通知一覧の取得・キャッシュ
///   - 未読数の管理（[unreadCount] ValueNotifier）
///   - Supabase Realtime による新着通知のリアルタイム受信
///   - 既読処理
///
/// 将来のプッシュ通知実装時は [registerFcmToken] を有効化する。
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  SupabaseClient get _client => SupabaseService.instance.client;

  /// 未読通知数。UI側は ValueListenableBuilder でリッスンする。
  final ValueNotifier<int> unreadCount = ValueNotifier(0);

  RealtimeChannel? _realtimeChannel;

  // ------------------------------------------------------------------
  // 初期化 / 破棄
  // ------------------------------------------------------------------

  /// ログイン後に呼び出す。未読数取得と Realtime 購読を開始する。
  Future<void> initialize() async {
    await refreshUnreadCount();
    _subscribeRealtime();
  }

  /// ログアウト時に呼び出す。購読を解除し未読数をリセットする。
  Future<void> dispose() async {
    await _realtimeChannel?.unsubscribe();
    _realtimeChannel = null;
    unreadCount.value = 0;
  }

  // ------------------------------------------------------------------
  // Realtime 購読
  // ------------------------------------------------------------------

  void _subscribeRealtime() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;

    _realtimeChannel?.unsubscribe();

    _realtimeChannel = _client
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) {
            // 新着通知が届いたら未読数をインクリメント
            unreadCount.value += 1;
          },
        )
        .subscribe();
  }

  // ------------------------------------------------------------------
  // 未読数
  // ------------------------------------------------------------------

  /// DBから未読数を取得して [unreadCount] を更新する。
  Future<void> refreshUnreadCount() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      final response = await _client
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('is_read', false);

      unreadCount.value = (response as List).length;
    } catch (e) {
      debugPrint('❌ NotificationService.refreshUnreadCount: $e');
    }
  }

  // ------------------------------------------------------------------
  // 通知一覧取得
  // ------------------------------------------------------------------

  /// 最新50件の通知を取得する。
  Future<List<AppNotification>> fetchNotifications() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _client
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);

      return (response as List)
          .map((json) => AppNotification.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('❌ NotificationService.fetchNotifications: $e');
      return [];
    }
  }

  // ------------------------------------------------------------------
  // 既読処理
  // ------------------------------------------------------------------

  /// 指定した通知を既読にする。
  Future<void> markAsRead(String notificationId) async {
    try {
      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);

      if (unreadCount.value > 0) {
        unreadCount.value -= 1;
      }
    } catch (e) {
      debugPrint('❌ NotificationService.markAsRead: $e');
    }
  }

  /// ログインユーザーの全通知を既読にする。
  Future<void> markAllAsRead() async {
    try {
      final userId = _client.auth.currentUser?.id;
      if (userId == null) return;

      await _client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', userId)
          .eq('is_read', false);

      unreadCount.value = 0;
    } catch (e) {
      debugPrint('❌ NotificationService.markAllAsRead: $e');
    }
  }

  // ------------------------------------------------------------------
  // 将来のプッシュ通知対応（スタブ）
  // ------------------------------------------------------------------

  /// FCM デバイストークンを profiles テーブルに保存する。
  ///
  /// 使用方法:
  ///   1. push_notifications_migration.sql を実行して
  ///      profiles.fcm_token カラムを追加する
  ///   2. pubspec.yaml に firebase_core / firebase_messaging を追加する
  ///   3. 以下のコメントを外して実装する
  Future<void> registerFcmToken(String token) async {
    // TODO: push_notifications_migration.sql 実行後に有効化する
    //
    // final userId = _client.auth.currentUser?.id;
    // if (userId == null) return;
    // await _client
    //     .from('profiles')
    //     .update({'fcm_token': token})
    //     .eq('id', userId);
    debugPrint('📌 registerFcmToken: 未実装（push_notifications_migration.sql 参照）');
  }
}
