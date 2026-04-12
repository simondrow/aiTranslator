import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../services/audio_service.dart';
import '../../../services/tts_service.dart';
import '../../../services/model_download_trigger.dart';
import '../../../utils/language_codes.dart';
import '../../model_manager/providers/model_manager_provider.dart';
import '../providers/conversation_provider.dart';
import '../widgets/language_bar.dart';
import 'conversation_mode_page.dart';

/// 主页 — Google Translate 风格
class ConversationPage extends ConsumerStatefulWidget {
  const ConversationPage({super.key});

  @override
  ConsumerState<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends ConsumerState<ConversationPage> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _textFocusNode = FocusNode();
  final AudioService _audioService = AudioService();
  final TtsService _ttsService = TtsService();

  bool _isRecording = false;
  bool _isCompleted = false;
  bool _firstInteraction = true; // 首次交互触发下载

  /// 防抖定时器 — 用户停顿后触发检测+翻译
  Timer? _debounceTimer;
  static const _debounceDuration = Duration(milliseconds: 400);

  @override
  void initState() {
    super.initState();
    _ttsService.initialize();
    _textController.addListener(_onTextChanged);
    _textFocusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _textController.removeListener(_onTextChanged);
    _textFocusNode.removeListener(_onFocusChanged);
    _textController.dispose();
    _textFocusNode.dispose();
    _audioService.dispose();
    _ttsService.dispose();
    super.dispose();
  }

  /// 首次用户交互时触发模型下载检查
  /// 触发条件: 首次输入文字、点击麦克风、切换语言
  Future<bool> _ensureModelReady() async {
    if (!_firstInteraction) return true;
    _firstInteraction = false;

    final notifier = ref.read(conversationProvider.notifier);

    // 如果翻译引擎已就绪，无需下载
    if (notifier.isTranslationReady) return true;

    // 弹出下载对话框
    final ready = await ModelDownloadTrigger.ensureNllbReady(context, ref);

    if (ready) {
      // 下载完成，初始化翻译引擎
      final modelDir = await ref.read(modelManagerProvider.notifier).getNllbModelDir();
      await notifier.initTranslationEngine(modelDir);
    } else {
      // 用户取消下载，允许再次触发
      _firstInteraction = true;
    }

    return ready;
  }

  /// 文字输入回调 — 带防抖的实时检测+翻译
  void _onTextChanged() {
    final text = _textController.text;

    // 清空输入 → 重置所有状态
    if (text.isEmpty) {
      _debounceTimer?.cancel();
      ref.read(conversationProvider.notifier).clearRealtime();
      if (_isCompleted) {
        setState(() => _isCompleted = false);
      }
      setState(() {});
      return;
    }

    // 已完成态下继续编辑 → 退回到输入态
    if (_isCompleted) {
      setState(() => _isCompleted = false);
    }

    // 防抖: 用户停止输入 400ms 后触发检测+翻译
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDuration, () async {
      final currentText = _textController.text.trim();
      if (currentText.isNotEmpty) {
        // 首次输入触发模型下载
        await _ensureModelReady();
        ref.read(conversationProvider.notifier).detectAndTranslate(currentText);
      }
    });

    setState(() {});
  }

  /// 用户按下回车/Done — 标记为完成态
  Future<void> _onSubmitted(String _) async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _debounceTimer?.cancel();
    _textFocusNode.unfocus();

    final notifier = ref.read(conversationProvider.notifier);
    final state = ref.read(conversationProvider);

    // 如果实时翻译已有结果，直接提交; 否则等待完整流程
    if (state.realtimeTranslation.isNotEmpty) {
      notifier.commitTranslation(text);
      setState(() => _isCompleted = true);
    } else {
      // 尚未拿到翻译结果，走完整流程
      await notifier.sendTextMessage(text);
      setState(() => _isCompleted = true);
    }
  }

  void _clearAll() {
    _debounceTimer?.cancel();
    ref.read(conversationProvider.notifier).clearRealtime();
    setState(() {
      _textController.clear();
      _isCompleted = false;
    });
  }

  Future<void> _toggleVoiceRecording() async {
    // 首次点击麦克风触发模型下载
    await _ensureModelReady();

    if (_isRecording) {
      setState(() => _isRecording = false);
      try {
        final path = await _audioService.stopRecording();
        if (path.isNotEmpty) {
          final notifier = ref.read(conversationProvider.notifier);
          await notifier.sendVoiceMessage(path);
          final state = ref.read(conversationProvider);
          if (state.messages.isNotEmpty) {
            final lastMsg = state.messages.last;
            setState(() {
              _textController.text = lastMsg.originalText;
              _isCompleted = true;
            });
          }
        }
      } catch (e) {
        debugPrint('Stop recording failed: $e');
      }
    } else {
      try {
        _textFocusNode.unfocus();
        await _audioService.startRecording();
        _debounceTimer?.cancel();
        ref.read(conversationProvider.notifier).clearRealtime();
        setState(() {
          _isRecording = true;
          _textController.clear();
          _isCompleted = false;
        });
      } catch (e) {
        debugPrint('Start recording failed: $e');
      }
    }
  }

  void _openHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryPage()),
    );
  }

  void _speakSource() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    final state = ref.read(conversationProvider);
    final lang = state.detectedSourceLang ?? state.myLanguage;
    _ttsService.speak(text, lang);
  }

  void _speakTarget() {
    final state = ref.read(conversationProvider);
    if (state.realtimeTranslation.isEmpty) return;
    final lang = state.detectedTargetLang ?? state.theirLanguage;
    _ttsService.speak(state.realtimeTranslation, lang);
  }

  /// 语言切换时触发模型下载
  void _onLanguageChanged() async {
    await _ensureModelReady();
  }

  /// 输入框失焦 → 视为输入完成，进入双语展示+发音界面
  void _onFocusChanged() {
    if (_textFocusNode.hasFocus) return; // 获焦时忽略

    final text = _textController.text.trim();
    if (text.isEmpty) return;
    if (_isCompleted) return; // 已经是完成态

    _debounceTimer?.cancel();

    final state = ref.read(conversationProvider);
    final notifier = ref.read(conversationProvider.notifier);

    if (state.realtimeTranslation.isNotEmpty) {
      // 已有翻译结果 → 直接提交
      notifier.commitTranslation(text);
      setState(() => _isCompleted = true);
    } else if (!state.isTranslating && !state.isDetecting) {
      // 尚无翻译且未在处理 → 发起完整翻译流程后进入完成态
      notifier.sendTextMessage(text).then((_) {
        if (mounted) setState(() => _isCompleted = true);
      });
    }
    // 如果正在翻译中，等翻译完成后再由用户操作
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(conversationProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final hasInput = _textController.text.isNotEmpty;
    final hasTranslation = state.realtimeTranslation.isNotEmpty;
    final isWorking = state.isDetecting || state.isTranslating;

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      appBar: AppBar(
        backgroundColor: AppTheme.surfaceWhite,
        leading: IconButton(
          icon: const Icon(Icons.history, size: 26),
          tooltip: '历史对话',
          onPressed: _openHistory,
        ),
        centerTitle: true,
        title: const Text(
          'AI Translator',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined, size: 26),
            tooltip: '模型管理',
            onPressed: () {
              Navigator.of(context).pushNamed('/model_download');
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => _textFocusNode.unfocus(),
                  behavior: HitTestBehavior.opaque,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 16),
                        _buildSourceArea(state),
                        if (hasInput || hasTranslation || isWorking)
                          ..._buildTranslationArea(state),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
              _buildBottomArea(state, bottomPadding),
            ],
          ),
          if (_isRecording) _buildRecordingOverlay(bottomPadding),
        ],
      ),
    );
  }

  /// 源文区域
  Widget _buildSourceArea(ConversationState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 完成态: 源语种标签
        if (_isCompleted && state.detectedSourceLang != null) ...[
          Text(
            LanguageCodes.getDisplayName(state.detectedSourceLang!),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.secondaryBlue,
            ),
          ),
          const SizedBox(height: 8),
        ],

        // 文本输入
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                focusNode: _textFocusNode,
                maxLines: 6,
                minLines: 1,
                style: const TextStyle(
                  fontSize: 28,
                  color: AppTheme.textPrimary,
                  height: 1.3,
                  fontWeight: FontWeight.w400,
                ),
                decoration: const InputDecoration(
                  hintText: '输入文字',
                  hintStyle: TextStyle(
                    fontSize: 28,
                    color: AppTheme.textHint,
                    height: 1.3,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                textInputAction: TextInputAction.done,
                onSubmitted: _onSubmitted,
              ),
            ),
            if (_textController.text.isNotEmpty && !_isCompleted)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: IconButton(
                  icon: const Icon(Icons.close, size: 22),
                  color: AppTheme.textSecondary,
                  onPressed: _clearAll,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),

        // 完成态: 🔊 📋
        if (_isCompleted && state.realtimeTranslation.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _ActionBtn(icon: Icons.volume_up_outlined, onTap: _speakSource),
              const Spacer(),
              _ActionBtn(
                icon: Icons.copy_outlined,
                onTap: () {
                  Clipboard.setData(
                      ClipboardData(text: _textController.text));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('已复制原文'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  /// 分隔线 + 译文区域
  List<Widget> _buildTranslationArea(ConversationState state) {
    return [
      const SizedBox(height: 12),
      // 蓝色分隔线
      Container(
        height: 2,
        decoration: BoxDecoration(
          color: AppTheme.secondaryBlue.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
      const SizedBox(height: 16),

      // 完成态: 目标语种标签
      if (_isCompleted && state.detectedTargetLang != null) ...[
        Text(
          LanguageCodes.getDisplayName(state.detectedTargetLang!),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.secondaryBlue,
          ),
        ),
        const SizedBox(height: 8),
      ],

      // 翻译中 / 译文
      if (state.isDetecting || state.isTranslating)
        const _ProcessingIndicator()
      else if (state.realtimeTranslation.isNotEmpty)
        Text(
          state.realtimeTranslation,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w500,
            color: AppTheme.targetTextColor,
            height: 1.3,
          ),
        ),

      // 完成态: 译文 🔊 📋
      if (_isCompleted && state.realtimeTranslation.isNotEmpty) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            _ActionBtn(icon: Icons.volume_up_outlined, onTap: _speakTarget),
            const Spacer(),
            _ActionBtn(
              icon: Icons.copy_outlined,
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: state.realtimeTranslation));
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
    ];
  }

  /// 底部区域: 语言栏 + 麦克风
  Widget _buildBottomArea(ConversationState state, double bottomPadding) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundGrey,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[350],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              LanguageBar(onLanguageChanged: _onLanguageChanged),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _toggleVoiceRecording,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFD3E3FD),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.secondaryBlue.withValues(alpha: 0.15),
                        blurRadius: 12,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.mic,
                    color: AppTheme.secondaryBlue,
                    size: 36,
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// 录音遮罩
  Widget _buildRecordingOverlay(double bottomPadding) {
    return Positioned.fill(
      child: GestureDetector(
        onTap: _toggleVoiceRecording,
        child: Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 3),
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.red.withValues(alpha: 0.12),
                  ),
                  child: Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.red,
                      ),
                      child: const Icon(
                        Icons.mic,
                        color: Colors.white,
                        size: 44,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  '正在录音...',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '点击任意位置停止',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
                const Spacer(flex: 2),
                Padding(
                  padding: EdgeInsets.only(bottom: 40 + bottomPadding),
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.stop,
                      color: Colors.white,
                      size: 32,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 操作按钮（🔊 📋）
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ActionBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 22, color: AppTheme.textSecondary),
      ),
    );
  }
}

/// 翻译中指示器
class _ProcessingIndicator extends StatelessWidget {
  const _ProcessingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        SizedBox(width: 12),
        Text(
          '翻译中...',
          style: TextStyle(fontSize: 20, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}
