import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../providers/model_manager_provider.dart';
import '../models/model_info.dart';
import '../../conversation/pages/conversation_page.dart';

/// 模型下载页面
class ModelDownloadPage extends ConsumerWidget {
  const ModelDownloadPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(modelManagerProvider);
    final notifier = ref.read(modelManagerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('模型管理'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 说明文字
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: AppTheme.primaryBlue),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '首次使用需要下载以下 AI 模型。\n模型将保存在本地，后续无需联网即可使用。',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 模型列表
            Expanded(
              child: ListView.builder(
                itemCount: state.models.length,
                itemBuilder: (context, index) {
                  return _ModelCard(model: state.models[index]);
                },
              ),
            ),

            // 错误提示
            if (state.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  state.errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ),

            // 底部操作按钮
            SizedBox(
              width: double.infinity,
              child: state.allModelsReady
                  ? ElevatedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const ConversationPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_circle),
                      label: const Text('开始使用'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed:
                          state.isDownloading ? null : () => notifier.downloadAllModels(),
                      icon: state.isDownloading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.download),
                      label: Text(state.isDownloading ? '下载中...' : '下载全部模型'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 单个模型卡片
class _ModelCard extends ConsumerWidget {
  final ModelInfo model;

  const _ModelCard({required this.model});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(modelManagerProvider.notifier);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 模型名和状态
            Row(
              children: [
                Icon(
                  model.isDownloaded
                      ? Icons.check_circle
                      : Icons.cloud_download_outlined,
                  color: model.isDownloaded ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    model.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${model.sizeInMB.toStringAsFixed(0)} MB',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 进度条
            if (!model.isDownloaded) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: model.downloadProgress > 0
                      ? model.downloadProgress
                      : null,
                  minHeight: 6,
                  backgroundColor: Colors.grey[200],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    model.downloadProgress > 0
                        ? '${(model.downloadProgress * 100).toStringAsFixed(1)}%'
                        : '等待下载',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  TextButton(
                    onPressed: () => notifier.downloadModel(model),
                    child: const Text('下载'),
                  ),
                ],
              ),
            ] else
              const Text(
                '✅ 已就绪',
                style: TextStyle(fontSize: 13, color: Colors.green),
              ),
          ],
        ),
      ),
    );
  }
}
