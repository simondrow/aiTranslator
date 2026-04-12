import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../services/tts_service.dart';
import '../../../utils/language_codes.dart';
import '../providers/conversation_provider.dart';
import '../models/message.dart';

/// 历史对话页面
/// 按左侧语言(myLanguage)和右侧语言(theirLanguage)的输入方向左右排布
/// 翻译结果显示在原文下方
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  final TtsService _ttsService = TtsService();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _ttsService.initialize();
  }

  @override
  void dispose() {
    _ttsService.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(conversationProvider);
    final messages = state.messages;

    return Scaffold(
      backgroundColor: AppTheme.backgroundGrey,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('历史对话'),
        actions: [
          if (messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清除全部',
              onPressed: () {
                _showClearConfirm(context);
              },
            ),
        ],
      ),
      body: messages.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  const Text(
                    '暂无翻译历史',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '在首页使用语音或文字输入进行翻译',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textHint,
                    ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final msg = messages[index];
                return Dismissible(
                  key: ValueKey('${msg.timestamp.millisecondsSinceEpoch}_$index'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.delete_outline,
                        color: Colors.redAccent, size: 28),
                  ),
                  confirmDismiss: (direction) async {
                    return true;
                  },
                  onDismissed: (direction) {
                    ref.read(conversationProvider.notifier).removeMessageAt(index);
                  },
                  child: _HistoryBubble(
                    message: msg,
                    onTtsOriginal: () {
                      _ttsService.speak(
                        msg.originalText,
                        msg.sourceLanguage,
                      );
                    },
                    onTtsTranslated: () {
                      _ttsService.speak(
                        msg.translatedText,
                        msg.targetLanguage,
                      );
                    },
                  ),
                );
              },
            ),
    );
  }

  void _showClearConfirm(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清除历史'),
        content: const Text('确定要清除所有翻译历史吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              ref.read(conversationProvider.notifier).clearMessages();
              Navigator.of(ctx).pop();
            },
            child: const Text('清除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

/// 历史对话气泡
/// isFromMe=true → 左侧语言输入 → 靠左排布
/// isFromMe=false → 右侧语言输入 → 靠右排布
class _HistoryBubble extends StatelessWidget {
  final Message message;
  final VoidCallback? onTtsOriginal;
  final VoidCallback? onTtsTranslated;

  const _HistoryBubble({
    required this.message,
    this.onTtsOriginal,
    this.onTtsTranslated,
  });

  @override
  Widget build(BuildContext context) {
    final isLeft = message.isFromMe; // "我的语言"即左侧语言

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isLeft ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isLeft) const Spacer(flex: 1),
          Flexible(
            flex: 4,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isLeft
                    ? AppTheme.surfaceWhite
                    : AppTheme.targetCardBg,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isLeft ? 4 : 16),
                  bottomRight: Radius.circular(isLeft ? 16 : 4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 语种标签 + 输入类型
                  Row(
                    children: [
                      Text(
                        '${LanguageCodes.getFlag(message.sourceLanguage)} '
                        '${LanguageCodes.getDisplayName(message.sourceLanguage)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      if (message.inputType == InputType.voice) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.mic, size: 12, color: AppTheme.textSecondary),
                      ],
                      const Spacer(),
                      Text(
                        _formatTime(message.timestamp),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textHint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 原文
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          message.originalText,
                          style: const TextStyle(
                            fontSize: 16,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      if (onTtsOriginal != null)
                        GestureDetector(
                          onTap: onTtsOriginal,
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8, top: 2),
                            child: Icon(Icons.volume_up_outlined,
                                size: 16, color: AppTheme.textSecondary),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 分隔线
                  Container(
                    height: 0.5,
                    color: AppTheme.dividerGrey,
                  ),
                  const SizedBox(height: 8),
                  // 翻译结果（在原文下方）
                  Row(
                    children: [
                      Text(
                        '${LanguageCodes.getFlag(message.targetLanguage)} ',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 2),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          message.translatedText,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.targetTextColor,
                          ),
                        ),
                      ),
                      if (onTtsTranslated != null)
                        GestureDetector(
                          onTap: onTtsTranslated,
                          child: const Padding(
                            padding: EdgeInsets.only(left: 8, top: 2),
                            child: Icon(Icons.volume_up_outlined,
                                size: 16, color: AppTheme.secondaryBlue),
                          ),
                        ),
                    ],
                  ),
                  // 底部操作
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _SmallAction(
                        icon: Icons.copy_outlined,
                        onTap: () {
                          Clipboard.setData(
                            ClipboardData(text: message.translatedText),
                          );
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('已复制翻译结果'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isLeft) const Spacer(flex: 1),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

class _SmallAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _SmallAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: AppTheme.textSecondary),
      ),
    );
  }
}
