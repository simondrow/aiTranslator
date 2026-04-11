import 'package:flutter/material.dart';

import '../features/conversation/pages/conversation_page.dart';
import '../features/conversation/pages/conversation_mode_page.dart';
import '../features/model_manager/pages/model_download_page.dart';

/// 应用内路由名称常量
class AppRoutes {
  AppRoutes._();

  static const String conversation = '/conversation';
  static const String history = '/history';
  static const String modelDownload = '/model_download';
}

/// 路由生成器
class AppRouter {
  AppRouter._();

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.conversation:
        return MaterialPageRoute(
          builder: (_) => const ConversationPage(),
        );

      case AppRoutes.history:
        return MaterialPageRoute(
          builder: (_) => const HistoryPage(),
        );

      case AppRoutes.modelDownload:
        return MaterialPageRoute(
          builder: (_) => const ModelDownloadPage(),
        );

      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('未找到路由: ${settings.name}'),
            ),
          ),
        );
    }
  }
}
