import 'package:flutter/material.dart';
import '../services/app_update_service.dart';

/// アップデート通知ダイアログ。
///
/// 状態遷移:
///   1. 初期表示: バージョン情報・リリースノートを表示
///   2. 権限未許可: 「提供元不明のアプリ」許可を求める画面
///   3. ダウンロード中: プログレスバー表示（キャンセル不可）
///   4. インストール準備完了: 「インストール」ボタン表示
class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  /// ダイアログを表示するショートカット。
  static Future<void> show(BuildContext context, UpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(updateInfo: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _UpdateStep { prompt, permissionRequired, downloading, readyToInstall }

class _UpdateDialogState extends State<UpdateDialog> with WidgetsBindingObserver {
  _UpdateStep _step = _UpdateStep.prompt;
  String? _downloadedPath;
  String? _errorMessage;

  final _service = AppUpdateService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 設定画面から戻ってきたときに権限を再チェックする。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _step == _UpdateStep.permissionRequired) {
      _resumeAfterSettings();
    }
  }

  Future<void> _resumeAfterSettings() async {
    final granted = await _service.canInstallPackages();
    if (!mounted) return;
    if (granted) {
      setState(() => _errorMessage = null);
      if (_downloadedPath != null) {
        // APK は既にダウンロード済み（インストール直前で権限が失われたケース）
        setState(() => _step = _UpdateStep.readyToInstall);
      } else {
        await _startDownload();
      }
    }
    // まだ未許可なら permissionRequired のまま待機（何もしない）
  }

  /// アップデートボタン押下: URLと権限を確認してからダウンロード開始。
  Future<void> _onUpdatePressed() async {
    if (widget.updateInfo.downloadUrl.isEmpty) {
      setState(() => _errorMessage = 'ダウンロードURLが取得できませんでした。');
      return;
    }

    final granted = await _service.canInstallPackages();
    if (!mounted) return;

    if (!granted) {
      setState(() {
        _step = _UpdateStep.permissionRequired;
        _errorMessage = null;
      });
      return;
    }

    await _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() {
      _step = _UpdateStep.downloading;
      _errorMessage = null;
    });

    final path = await _service.downloadApk(widget.updateInfo.downloadUrl);

    if (!mounted) return;

    if (path != null) {
      setState(() {
        _downloadedPath = path;
        _step = _UpdateStep.readyToInstall;
      });
    } else {
      setState(() {
        _step = _UpdateStep.prompt;
        _errorMessage = 'ダウンロードに失敗しました。もう一度お試しください。';
      });
    }
  }

  Future<void> _install() async {
    if (_downloadedPath == null) return;

    // インストール直前にも権限を再確認
    final granted = await _service.canInstallPackages();
    if (!mounted) return;

    if (!granted) {
      setState(() {
        _step = _UpdateStep.permissionRequired;
        _errorMessage = null;
      });
      return;
    }

    final success = await _service.installApk(_downloadedPath!);
    if (!mounted) return;
    if (success) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _errorMessage = 'インストーラーの起動に失敗しました。もう一度お試しください。';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // ダウンロード中は戻るボタンを無効化
      canPop: _step != _UpdateStep.downloading,
      child: AlertDialog(
        backgroundColor: const Color(0xFF272727),
        title: Row(
          children: [
            Icon(
              _step == _UpdateStep.permissionRequired
                  ? Icons.security
                  : Icons.system_update,
              color: const Color(0xFFF20D0D),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _step == _UpdateStep.permissionRequired
                    ? 'インストール許可が必要です'
                    : 'アップデートがあります',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
        content: _buildContent(),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildContent() {
    if (_step == _UpdateStep.permissionRequired) {
      return _buildPermissionContent();
    }

    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // バージョン情報
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'v${widget.updateInfo.versionName}',
              style: const TextStyle(
                color: Color(0xFFF20D0D),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // リリースノート
          if (widget.updateInfo.releaseNotes.isNotEmpty) ...[
            const Text(
              '変更内容',
              style: TextStyle(
                color: Color(0xFFAAAAAA),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.updateInfo.releaseNotes,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 12),
          ],

          // ダウンロード進捗
          if (_step == _UpdateStep.downloading) ...[
            const Text(
              'ダウンロード中...',
              style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 13),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<double>(
              valueListenable: _service.downloadProgress,
              builder: (_, progress, __) {
                // progress == -1.0 は Content-Length 不明（不定表示）
                final isIndeterminate = progress < 0;
                return Column(
                  children: [
                    LinearProgressIndicator(
                      value: isIndeterminate ? null : progress,
                      backgroundColor: const Color(0xFF1A1A1A),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFFF20D0D)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isIndeterminate
                          ? 'ダウンロード中...'
                          : '${(progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
                    ),
                  ],
                );
              },
            ),
          ],

          // エラーメッセージ
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFFFF5555), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionContent() {
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 説明テキスト
          const Text(
            'SabaTube のアップデートをインストールするには、「提供元不明のアプリ」のインストール許可が必要です。',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // 手順
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '許可の手順',
                  style: TextStyle(
                    color: Color(0xFFAAAAAA),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  '1. 下の「設定を開く」ボタンをタップ\n'
                  '2.「この提供元のアプリを許可」をオン\n'
                  '3. アプリに戻るとダウンロードが始まります',
                  style: TextStyle(color: Color(0xFFCCCCCC), fontSize: 12, height: 1.6),
                ),
              ],
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFFFF5555), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildActions() {
    if (_step == _UpdateStep.downloading) {
      return [
        const Padding(
          padding: EdgeInsets.only(right: 16, bottom: 8),
          child: Text(
            'ダウンロードが完了するまでお待ちください',
            style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 11),
          ),
        ),
      ];
    }

    if (_step == _UpdateStep.permissionRequired) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('後で', style: TextStyle(color: Color(0xFFAAAAAA))),
        ),
        ElevatedButton.icon(
          onPressed: () async {
            final opened = await _service.openInstallPermissionSettings();
            if (!mounted) return;
            if (!opened) {
              setState(() => _errorMessage = '設定画面を開けませんでした。手動で設定 → アプリ → SabaTube から許可してください。');
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF20D0D),
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.settings, size: 16),
          label: const Text('設定を開く'),
        ),
      ];
    }

    if (_step == _UpdateStep.readyToInstall) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('後で', style: TextStyle(color: Color(0xFFAAAAAA))),
        ),
        ElevatedButton(
          onPressed: _install,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF20D0D),
            foregroundColor: Colors.white,
          ),
          child: const Text('インストール'),
        ),
      ];
    }

    // prompt ステップ
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('後で', style: TextStyle(color: Color(0xFFAAAAAA))),
      ),
      ElevatedButton(
        onPressed: _onUpdatePressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF20D0D),
          foregroundColor: Colors.white,
        ),
        child: const Text('アップデート'),
      ),
    ];
  }
}
