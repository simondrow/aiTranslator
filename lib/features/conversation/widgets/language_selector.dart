import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../utils/language_codes.dart';

/// 单语言选择器 BottomSheet（Google Translate 风格）
class LanguagePickerSheet extends StatelessWidget {
  final String title;
  final String selectedCode;
  final void Function(String code) onSelect;

  const LanguagePickerSheet({
    super.key,
    required this.title,
    required this.selectedCode,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 顶部拖拽指示条 + 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                ],
              ),
            ),
            // 语言列表
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: SupportedLanguage.values.length,
                itemBuilder: (context, index) {
                  final lang = SupportedLanguage.values[index];
                  final isSelected = lang.code == selectedCode;
                  return ListTile(
                    leading: Text(
                      lang.flag,
                      style: const TextStyle(fontSize: 24),
                    ),
                    title: Text(
                      lang.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected
                            ? AppTheme.secondaryBlue
                            : AppTheme.textPrimary,
                      ),
                    ),
                    subtitle: Text(
                      lang.nativeName,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check, color: AppTheme.secondaryBlue)
                        : null,
                    onTap: () => onSelect(lang.code),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 保留旧的 LanguageSelectorSheet 以兼容 router.dart
class LanguageSelectorSheet extends StatelessWidget {
  const LanguageSelectorSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Language Selector')),
    );
  }
}
