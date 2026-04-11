import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/theme.dart';
import 'app/router.dart';
import 'features/conversation/pages/conversation_page.dart';

void main() {
  runApp(
    const ProviderScope(
      child: AITranslatorApp(),
    ),
  );
}

class AITranslatorApp extends StatelessWidget {
  const AITranslatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Translator',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const ConversationPage(),
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
