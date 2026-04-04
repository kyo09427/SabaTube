import 'package:flutter/material.dart';
import '../../models/user_profile.dart';
import '../../widgets/app_mobile_top_bar.dart';
import '../channel/channel_screen.dart';

/// 登録チャンネル一覧画面（スマホ版）
///
/// 「すべて」ボタンから遷移する縦リスト形式のチャンネル一覧。
class SubscriptionsChannelListScreen extends StatelessWidget {
  final List<UserProfile> channels;

  const SubscriptionsChannelListScreen({
    super.key,
    required this.channels,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurfaceVariant;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            // ── 共通上部バー ──
            SliverAppBar(
              pinned: true,
              backgroundColor: bg.withValues(alpha: 0.95),
              elevation: 0,
              titleSpacing: 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back, color: textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: AppMobileTopBar.buildTitle(context),
              actions: AppMobileTopBar.buildActions(context),
            ),

            // ── ソートボタン ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: InkWell(
                  onTap: () {},
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '関連度順',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.expand_more, size: 18, color: textPrimary),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── チャンネルリスト ──
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final channel = channels[index];
                  return InkWell(
                    onTap: () {
                      Navigator.of(context)
                          .push(ChannelScreen.route(channel.id));
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: Row(
                        children: [
                          // アバター（48px）
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: Colors.purple,
                            backgroundImage: channel.avatarUrl != null
                                ? NetworkImage(channel.avatarUrl!)
                                : null,
                            child: channel.avatarUrl == null
                                ? Text(
                                    channel.initials,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 14),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 16),

                          // チャンネル情報
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  channel.username,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: textPrimary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (channel.bio != null &&
                                    channel.bio!.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    channel.bio!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: textSecondary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                childCount: channels.length,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }
}
