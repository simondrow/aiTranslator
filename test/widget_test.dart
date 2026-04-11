import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ai_translator/main.dart';

void main() {
  testWidgets('App launches and shows title', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: AITranslatorApp()),
    );

    // Verify app title is displayed
    expect(find.text('AI Translator'), findsOneWidget);

    // Verify hint text is displayed
    expect(find.text('输入文字'), findsOneWidget);
  });
}
