import 'package:flutter/material.dart';
import '../../models/notification_model.dart';
import '../../services/notification_service.dart';
import '../channel/channel_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  static const Color _background = Color(0xFF0F0F0F);
  static const Color _surface = Color(0xFF272727);
  static const Color _surfaceUnread = Color(0xFF1E2A3A);
  static const Color _textWhite = Colors.white;
  static const Color _textGray = Color(0xFFAAAAAA);
  static const Color _ytRed = Color(0xFFF20D0D);

  List<AppNotification> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final result = await NotificationService.instance.fetchNotifications();
    if (mounted) {
      setState(() {
        _notifications = result;
        _isLoading = false;
      });
    }
  }

  Future<void> _onTapNotification(AppNotification notification) async {
    // 未読なら既読にする
    if (!notification.isRead) {
      await NotificationService.instance.markAsRead(notification.id);
      if (mounted) {
        setState(() {
          final index = _notifications.indexWhere((n) => n.id == notification.id);
          if (index != -1) {
            _notifications[index] = notification.copyWith(isRead: true);
          }
        });
      }
    }

    // チャンネルIDがあればチャンネル画面へ遷移
    final channelId = notification.channelId;
    if (channelId != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChannelScreen(channelId: channelId),
        ),
      );
    }
  }

  Future<void> _markAllAsRead() async {
    await NotificationService.instance.markAllAsRead();
    if (mounted) {
      setState(() {
        _notifications = _notifications
            .map((n) => n.copyWith(isRead: true))
            .toList();
      });
    }
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);

    if (diff.inSeconds < 60) return 'たった今';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    if (diff.inHours < 24) return '${diff.inHours}時間前';
    if (diff.inDays < 7) return '${diff.inDays}日前';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}週間前';
    if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}ヶ月前';
    return '${(diff.inDays / 365).floor()}年前';
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _notifications.any((n) => !n.isRead);

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _background,
        foregroundColor: _textWhite,
        elevation: 0,
        title: const Text(
          '通知',
          style: TextStyle(
            color: _textWhite,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text(
                'すべて既読',
                style: TextStyle(color: _textGray, fontSize: 13),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _ytRed))
          : RefreshIndicator(
              onRefresh: _load,
              color: _ytRed,
              backgroundColor: _surface,
              child: _notifications.isEmpty
                  ? _buildEmpty()
                  : ListView.builder(
                      itemCount: _notifications.length,
                      itemBuilder: (context, index) {
                        return _buildItem(_notifications[index]);
                      },
                    ),
            ),
    );
  }

  Widget _buildItem(AppNotification notification) {
    return InkWell(
      onTap: () => _onTapNotification(notification),
      child: Container(
        color: notification.isRead ? Colors.transparent : _surfaceUnread,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // アイコン
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _surface,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.video_library_outlined,
                color: _ytRed,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            // テキスト
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: TextStyle(
                      color: _textWhite,
                      fontSize: 14,
                      fontWeight: notification.isRead
                          ? FontWeight.normal
                          : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: const TextStyle(color: _textGray, fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatRelativeTime(notification.createdAt),
                    style: const TextStyle(color: _textGray, fontSize: 12),
                  ),
                ],
              ),
            ),
            // 未読ドット
            if (!notification.isRead)
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 8),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: _ytRed,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Center(
          child: Column(
            children: [
              Icon(Icons.notifications_none_outlined,
                  size: 72, color: _surface),
              SizedBox(height: 16),
              Text(
                '通知はありません',
                style: TextStyle(color: _textGray, fontSize: 15),
              ),
              SizedBox(height: 8),
              Text(
                'チャンネルを登録すると\n新着動画の通知が届きます',
                textAlign: TextAlign.center,
                style: TextStyle(color: _textGray, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
