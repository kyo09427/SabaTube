import 'package:flutter/material.dart';
import '../models/user_profile.dart';
import '../screens/channel/channel_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/post/post_video_screen.dart';
import '../screens/profile/my_page_screen.dart';
import '../screens/subscriptions/subscriptions_screen.dart';
import '../screens/timeline/timeline_screen.dart';
import '../services/supabase_service.dart';
import 'app_bottom_navigation_bar.dart';

/// 幅に応じてサイドバー（PC）またはボトムナビ（モバイル）を切り替える Scaffold ラッパー
///
/// - 幅 800px 以上 → 左サイドバー表示、ボトムナビ非表示
/// - 幅 800px 未満 → ボトムナビ表示、サイドバー非表示
class AppNavigationScaffold extends StatelessWidget {
  final int currentIndex;
  final Widget body;
  final Color? backgroundColor;
  final PreferredSizeWidget? appBar;
  final String? currentChannelId;

  const AppNavigationScaffold({
    super.key,
    required this.currentIndex,
    required this.body,
    this.backgroundColor,
    this.appBar,
    this.currentChannelId,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1100) {
          // PC: サイドバーレイアウト（ボトムナビなし）
          return Scaffold(
            backgroundColor: backgroundColor,
            appBar: appBar,
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppSideNavigation(
                  currentIndex: currentIndex,
                  currentChannelId: currentChannelId,
                ),
                Expanded(child: body),
              ],
            ),
          );
        }
        // モバイル: ボトムナビレイアウト
        return Scaffold(
          backgroundColor: backgroundColor,
          appBar: appBar,
          body: body,
          bottomNavigationBar: AppBottomNavigationBar(currentIndex: currentIndex),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PC 用左サイドバーナビゲーション
// ─────────────────────────────────────────────────────────────────────────────

class AppSideNavigation extends StatefulWidget {
  final int currentIndex;
  final String? currentChannelId;

  const AppSideNavigation({
    super.key,
    required this.currentIndex,
    this.currentChannelId,
  });

  @override
  State<AppSideNavigation> createState() => _AppSideNavigationState();
}

class _AppSideNavigationState extends State<AppSideNavigation> {
  static const double _width = 220;
  static const int _maxVisible = 5;

  static List<UserProfile>? _cachedChannels;

  List<UserProfile> _channels = [];
  bool _showAll = false;

  @override
  void initState() {
    super.initState();
    if (_cachedChannels != null) {
      _channels = _cachedChannels!;
    } else {
      _loadChannels();
    }
  }

  Future<void> _loadChannels() async {
    try {
      final channelIds = await SupabaseService.instance.getSubscribedChannelIds();
      if (channelIds.isEmpty || !mounted) return;

      final response = await SupabaseService.instance.client
          .from('profiles')
          .select('*')
          .inFilter('id', channelIds);

      final channels = (response as List)
          .whereType<Map<String, dynamic>>()
          .map((p) => UserProfile.fromJson(p))
          .toList();

      _cachedChannels = channels;
      if (mounted) setState(() => _channels = channels);
    } catch (_) {
      // チャンネルが読み込めない場合は空のまま
    }
  }

  /// キャッシュを破棄して再ロードする（チャンネル登録・解除後に呼ぶ）
  static void invalidateCache() {
    _cachedChannels = null;
  }

  void _onItemTapped(int index) {
    if (index == widget.currentIndex) return;

    switch (index) {
      case 0:
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        break;
      case 1:
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const TimelineScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        break;
      case 2:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const PostVideoScreen()),
        );
        break;
      case 3:
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const SubscriptionsScreen(),
            transitionDuration: Duration.zero,
            reverseTransitionDuration: Duration.zero,
          ),
        );
        break;
      case 4:
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

  // ── ナビゲーション項目 ────────────────────────────────────────────────────

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    bool showTrailingChevron = false,
  }) {
    final isActive = index == widget.currentIndex;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: InkWell(
        onTap: () => _onItemTapped(index),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? colorScheme.primaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(
                isActive ? activeIcon : icon,
                size: 22,
                color: isActive
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        isActive ? FontWeight.w600 : FontWeight.normal,
                    color: isActive
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showTrailingChevron) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: isActive
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPostButton() {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: InkWell(
        onTap: () => _onItemTapped(2),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.add_circle_outline,
                  size: 22, color: colorScheme.onSurface),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '動画を投稿',
                  style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 登録チャンネルリスト ──────────────────────────────────────────────────

  Widget _buildChannelSection() {
    if (_channels.isEmpty) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final visible =
        _showAll ? _channels : _channels.take(_maxVisible).toList();
    final hasMore = _channels.length > _maxVisible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── チャンネル一覧 ──
        ...visible.map((ch) => _buildChannelItem(ch)),

        // ── もっと見る / 閉じる ──
        if (hasMore)
          InkWell(
            onTap: () => setState(() => _showAll = !_showAll),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _showAll
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _showAll ? '閉じる' : 'もっと見る',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildChannelItem(UserProfile channel) {
    final colorScheme = Theme.of(context).colorScheme;
    final isActive = channel.id == widget.currentChannelId;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(ChannelScreen.route(channel.id));
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
        padding: const EdgeInsets.only(left: 12, right: 12, top: 7, bottom: 7),
        decoration: BoxDecoration(
          color: isActive ? colorScheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 12,
              backgroundColor: Colors.purple,
              backgroundImage: channel.avatarUrl != null
                  ? NetworkImage(channel.avatarUrl!)
                  : null,
              child: channel.avatarUrl == null
                  ? Text(
                      channel.initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                channel.username ?? '不明',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: isActive ? colorScheme.primary : colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: _width,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        right: false,
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── ロゴ ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Row(
                  children: [
                    Image.asset('icon.png', height: 28),
                    const SizedBox(width: 8),
                    Text(
                      'SabaTube',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                indent: 16,
                endIndent: 16,
              ),
              const SizedBox(height: 8),

              // ── ナビゲーション項目 ──
              _buildNavItem(
                index: 0,
                icon: Icons.home_outlined,
                activeIcon: Icons.home_filled,
                label: 'ホーム',
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.timeline_outlined,
                activeIcon: Icons.timeline,
                label: 'タイムライン',
              ),
              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                indent: 16,
                endIndent: 16,
              ),
              const SizedBox(height: 4),
              _buildNavItem(
                index: 3,
                icon: Icons.subscriptions_outlined,
                activeIcon: Icons.subscriptions,
                label: '登録チャンネル',
                showTrailingChevron: true,
              ),

              // ── 登録チャンネルリスト（登録チャンネル直下） ──
              _buildChannelSection(),

              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                indent: 16,
                endIndent: 16,
              ),
              const SizedBox(height: 4),
              _buildNavItem(
                index: 4,
                icon: Icons.account_circle_outlined,
                activeIcon: Icons.account_circle,
                label: 'マイページ',
              ),

              const SizedBox(height: 8),
              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                indent: 16,
                endIndent: 16,
              ),
              const SizedBox(height: 8),

              // ── 投稿ボタン ──
              _buildPostButton(),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
