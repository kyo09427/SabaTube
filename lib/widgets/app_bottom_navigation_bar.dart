import 'package:flutter/material.dart';
import '../screens/home/home_screen.dart';
import '../screens/post/post_video_screen.dart';
import '../screens/profile/my_page_screen.dart';
import '../screens/subscriptions/subscriptions_screen.dart';
import '../screens/timeline/timeline_screen.dart';

/// 共通のボトムナビゲーションバー
class AppBottomNavigationBar extends StatelessWidget {
  final int currentIndex;

  const AppBottomNavigationBar({
    super.key,
    required this.currentIndex,
  });

  // デザイン用カラー（テーマから動的取得）
  Color _ytBackground(BuildContext context) => Theme.of(context).scaffoldBackgroundColor;
  Color _ytSurface(BuildContext context) => Theme.of(context).colorScheme.surface;
  Color _textColor(BuildContext context) => Theme.of(context).colorScheme.onSurface;

  void _onItemTapped(BuildContext context, int index) {
    // 現在のページと同じ場合は何もしない
    if (index == currentIndex) return;

    switch (index) {
      case 0: // ホーム
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        break;
      case 1: // タイムライン
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const TimelineScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        break;
      case 2: // 投稿
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PostVideoScreen()),
        );
        break;
      case 3: // 登録チャンネル
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const SubscriptionsScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        break;
      case 4: // マイページ
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const MyPageScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        break;
    }
  }

  Widget _buildNavItem({
    required BuildContext context,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    required int index,
    VoidCallback? onTap,
  }) {
    final isActive = index == currentIndex;
    final colorScheme = Theme.of(context).colorScheme;
    final itemColor = isActive ? colorScheme.primary : colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap ?? () => _onItemTapped(context, index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: isActive ? colorScheme.primaryContainer : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              isActive ? activeIcon : icon,
              color: itemColor,
              size: 24,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: itemColor,
              fontSize: 10,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _ytBackground(context);
    final surfaceColor = _ytSurface(context);
    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(top: BorderSide(color: surfaceColor, width: 0.5)),
      ),
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(
            context: context,
            icon: Icons.home_outlined,
            activeIcon: Icons.home_filled,
            label: 'ホーム',
            index: 0,
          ),
          _buildNavItem(
            context: context,
            icon: Icons.timeline_outlined,
            activeIcon: Icons.timeline,
            label: 'タイムライン',
            index: 1,
          ),
          // 投稿ボタン（中央）
          InkWell(
            onTap: () => _onItemTapped(context, 2),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _textColor(context).withValues(alpha: 0.2),
                  width: 1,
                ),
                color: _ytSurface(context).withValues(alpha: 0.5),
              ),
              child: Icon(Icons.add, color: _textColor(context), size: 28),
            ),
          ),
          _buildNavItem(
            context: context,
            icon: Icons.subscriptions_outlined,
            activeIcon: Icons.subscriptions,
            label: '登録チャンネル',
            index: 3,
          ),
          _buildNavItem(
            context: context,
            icon: Icons.account_circle_outlined,
            activeIcon: Icons.account_circle,
            label: 'マイページ',
            index: 4,
          ),
        ],
      ),
    );
  }
}