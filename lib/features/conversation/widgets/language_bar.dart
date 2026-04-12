import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme.dart';
import '../../../utils/language_codes.dart';
import '../providers/conversation_provider.dart';
import 'language_selector.dart';

/// 语言选择栏 — 胶囊按钮风格，参考 Google Translate
class LanguageBar extends ConsumerWidget {
  /// 语言切换后的回调
  final VoidCallback? onLanguageChanged;

  /// 是否可交互（录音时置灰）
  final bool enabled;

  const LanguageBar({
    super.key,
    this.onLanguageChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(conversationProvider);
    final myLang = state.myLanguage;
    final theirLang = state.theirLanguage;

    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Row(
          children: [
            // 左侧语言
            Expanded(
              child: _LangPill(
                label: LanguageCodes.getDisplayName(myLang),
                onTap: () => _showPicker(context, ref, isSource: true),
              ),
            ),
            // 中间切换 icon
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Icon(
                Icons.swap_horiz,
                color: AppTheme.textSecondary,
                size: 28,
              ),
            ),
            // 右侧语言
            Expanded(
              child: _LangPill(
                label: LanguageCodes.getDisplayName(theirLang),
                onTap: () => _showPicker(context, ref, isSource: false),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context, WidgetRef ref,
      {required bool isSource}) {
    final state = ref.read(conversationProvider);
    final notifier = ref.read(conversationProvider.notifier);
    final currentCode = isSource ? state.myLanguage : state.theirLanguage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => LanguagePickerSheet(
        title: isSource ? '左侧语言' : '右侧语言',
        selectedCode: currentCode,
        onSelect: (code) {
          if (isSource) {
            notifier.setMyLanguage(code);
          } else {
            notifier.setTheirLanguage(code);
          }
          Navigator.of(context).pop();
          onLanguageChanged?.call();
        },
      ),
    );
  }
}

/// 胶囊形语言按钮
class _LangPill extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _LangPill({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surfaceWhite,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: AppTheme.dividerGrey,
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
