import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/model_manager/providers/model_manager_provider.dart';
import '../features/model_manager/models/model_info.dart';

/// 按需模型下载触发器
class ModelDownloadTrigger {
  static bool _isDialogShowing = false;
  static bool _hasTriggered = false;

  /// 检查翻译模型是否需要下载，如需要则弹出 loading 对话框
  static Future<bool> ensureTranslationReady(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final state = ref.read(modelManagerProvider);

    if (state.isHymtReady) return true;
    if (_isDialogShowing) return false;

    _hasTriggered = true;
    _isDialogShowing = true;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: const _HymtDownloadDialog(),
      ),
    );

    _isDialogShowing = false;
    return result ?? false;
  }

  static bool get hasTriggered => _hasTriggered;

  static void reset() {
    _hasTriggered = false;
    _isDialogShowing = false;
  }
}

class _HymtDownloadDialog extends ConsumerStatefulWidget {
  const _HymtDownloadDialog();

  @override
  ConsumerState<_HymtDownloadDialog> createState() =>
      _HymtDownloadDialogState();
}

class _HymtDownloadDialogState extends ConsumerState<_HymtDownloadDialog> {
  bool _downloading = false;
  bool _completed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _startDownload());
  }

  Future<void> _startDownload() async {
    if (!mounted) return;
    setState(() {
      _downloading = true;
      _error = null;
    });

    try {
      final notifier = ref.read(modelManagerProvider.notifier);

      // 确保模型列表已初始化
      await notifier.ensureInitialized();

      await notifier.downloadHymtIfNeeded();

      if (mounted) {
        setState(() {
          _downloading = false;
          _completed = true;
        });
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ConsumerStatefulWidget 的 ref.watch 会自动触发 rebuild
    final state = ref.watch(modelManagerProvider);

    ModelInfo hymtModel;
    try {
      hymtModel = state.models.firstWhere(
        (m) => m.modelType == ModelInfo.hymtModelType,
      );
    } catch (_) {
      hymtModel = ModelInfo(
        name: 'HY-MT1.5',
        url: '',
        fileName: ModelInfo.hymtModelDirName,
        sizeInMB: ModelInfo.hymtTotalSizeMB,
        modelType: ModelInfo.hymtModelType,
      );
    }

    final progress = hymtModel.downloadProgress;
    final progressPercent = (progress * 100).toStringAsFixed(0);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _completed
                    ? Icons.check_circle_outline
                    : _error != null
                        ? Icons.error_outline
                        : Icons.translate,
                size: 48,
                color: _completed
                    ? Colors.green
                    : _error != null
                        ? Colors.red
                        : Colors.blue,
              ),
              const SizedBox(height: 16),
              Text(
                _completed
                    ? '翻译引擎已就绪'
                    : _error != null
                        ? '下载失败'
                        : '正在下载翻译模型',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (!_completed && _error == null)
                Text(
                  'HY-MT1.5 Q4 (~${ModelInfo.hymtTotalSizeMB.toStringAsFixed(0)} MB)',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
              if (_downloading) ...[
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 6,
                    backgroundColor: Colors.grey[200],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  progress > 0 ? '$progressPercent%' : '准备中...',
                  style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!.length > 100
                      ? '${_error!.substring(0, 100)}...'
                      : _error!,
                  style: const TextStyle(fontSize: 13, color: Colors.red),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        if (_error != null) ...[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: _startDownload,
            child: const Text('重试'),
          ),
        ],
        if (_downloading)
          TextButton(
            onPressed: () {
              ref.read(modelManagerProvider.notifier).cancelDownload();
              Navigator.of(context).pop(false);
            },
            child: const Text('取消'),
          ),
      ],
    );
  }
}
