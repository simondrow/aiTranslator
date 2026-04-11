import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../services/audio_service.dart';
import '../../../services/tts_service.dart';
import '../../../utils/language_codes.dart';
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

  String _currentTranslation = '';
  String? _detectedSourceLang;
  String? _detectedTargetLang;
  bool _isRecording = false;
  bool _isCompleted = false;

  @override
  void initState() {
    super.initState();
    _ttsService.initialize();
    _textController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _textController.removeListener(_onTextChanged);
    _textController.dispose();
    _textFocusNode.dispose();
    _audioService.dispose();
    _ttsService.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (_isCompleted && _textController.text.isEmpty) {
      setState(() {
        _isCompleted = false;
        _currentTranslation = '';
        _detectedSourceLang = null;
        _detectedTargetLang = null;
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _sendTextMessage() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _textFocusNode.unfocus();

    final notifier = ref.read(conversationProvider.notifier);
    await notifier.sendTextMessage(text);

    final state = ref.read(conversationProvider);
    if (state.messages.isNotEmpty) {
      final lastMsg = state.messages.last;
      setState(() {
        _currentTranslation = lastMsg.translatedText;
        _detectedSourceLang = lastMsg.sourceLanguage;
        _detectedTargetLang = lastMsg.targetLanguage;
        _isCompleted = true;
      });
    }
  }

  void _clearAll() {
    setState(() {
      _textController.clear();
      _currentTranslation = '';
      _detectedSourceLang = null;
      _detectedTargetLang = null;
      _isCompleted = false;
    });
  }

  Future<void> _toggleVoiceRecording() async {
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
              _currentTranslation = lastMsg.translatedText;
              _detectedSourceLang = lastMsg.sourceLanguage;
              _detectedTargetLang = lastMsg.targetLanguage;
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
        setState(() {
          _isRecording = true;
          _textController.clear();
          _currentTranslation = '';
          _detectedSourceLang = null;
          _detectedTargetLang = null;
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
    final lang = _detectedSourceLang ?? ref.read(conversationProvider).myLanguage;
    _ttsService.speak(text, lang);
  }

  void _speakTarget() {
    if (_currentTranslation.isEmpty) return;
    final lang = _detectedTargetLang ?? ref.read(conversationProvider).theirLanguage;
    _ttsService.speak(_currentTranslation, lang);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(conversationProvider);
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: AppTheme.surfaceWhite,
      // ---- AppBar: 左上角历史按钮, 中间标题, 右侧模型管理 ----
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
          // ==== 主内容 ====
          Column(
            children: [
              // ---- 翻译内容区 ----
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
                        _buildSourceArea(context, state),
                        if (_textController.text.isNotEmpty ||
                            _currentTranslation.isNotEmpty ||
                            state.isProcessing)
                          ..._buildTranslationArea(context, state),
                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ),
              ),
              // ---- 底部区域 ----
              _buildBottomArea(context, state, bottomPadding),
            ],
          ),

          // ==== 录音遮罩 ====
          if (_isRecording) _buildRecordingOverlay(bottomPadding),
        ],
      ),
    );
  }

  /// 源文区域 — 无边框纯文字输入
  Widget _buildSourceArea(BuildContext context, ConversationState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 完成态: 源语种标签
        if (_isCompleted && _detectedSourceLang != null) ...[
          Text(
            LanguageCodes.getDisplayName(_detectedSourceLang!),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppTheme.secondaryBlue,
            ),
          ),
          const SizedBox(height: 8),
        ],

        // 文本输入 — 大字号，无边框
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
                onSubmitted: (_) => _sendTextMessage(),
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

        // 完成态: 原文下方 🔊 📋
        if (_isCompleted && _currentTranslation.isNotEmpty) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _ActionBtn(icon: Icons.volume_up_outlined, onTap: _speakSource),
              const Spacer(),
              _ActionBtn(
                icon: Icons.copy_outlined,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _textController.text));
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
  List<Widget> _buildTranslationArea(
      BuildContext context, ConversationState state) {
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
      if (_isCompleted && _detectedTargetLang != null) ...[
        Text(
          LanguageCodes.getDisplayName(_detectedTargetLang!),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.secondaryBlue,
          ),
        ),
        const SizedBox(height: 8),
      ],

      // 译文
      if (state.isProcessing)
        const _ProcessingIndicator()
      else if (_currentTranslation.isNotEmpty)
        Text(
          _currentTranslation,
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w500,
            color: AppTheme.targetTextColor,
            height: 1.3,
          ),
        ),

      // 完成态: 译文下方 🔊 📋
      if (_isCompleted && _currentTranslation.isNotEmpty) ...[
        const SizedBox(height: 8),
        Row(
          children: [
            _ActionBtn(icon: Icons.volume_up_outlined, onTap: _speakTarget),
            const Spacer(),
            _ActionBtn(
              icon: Icons.copy_outlined,
              onTap: () {
                Clipboard.setData(ClipboardData(text: _currentTranslation));
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
  Widget _buildBottomArea(
      BuildContext context, ConversationState state, double bottomPadding) {
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
              // 拖拽指示条
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
              // 语言选择栏
              const LanguageBar(),
              const SizedBox(height: 20),
              // 麦克风按钮（大）
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
                // 录音指示
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
                // 底部停止按钮
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
