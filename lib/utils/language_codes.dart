/// 支持的语言枚举
enum SupportedLanguage {
  chinese(
    code: 'zh',
    displayName: '中文',
    nativeName: '中文',
    nllbCode: 'zho_Hans',
    whisperCode: 'zh',
    flag: '🇨🇳',
  ),
  english(
    code: 'en',
    displayName: '英文',
    nativeName: 'English',
    nllbCode: 'eng_Latn',
    whisperCode: 'en',
    flag: '🇺🇸',
  ),
  japanese(
    code: 'ja',
    displayName: '日文',
    nativeName: '日本語',
    nllbCode: 'jpn_Jpan',
    whisperCode: 'ja',
    flag: '🇯🇵',
  ),
  korean(
    code: 'ko',
    displayName: '韩文',
    nativeName: '한국어',
    nllbCode: 'kor_Hang',
    whisperCode: 'ko',
    flag: '🇰🇷',
  ),
  french(
    code: 'fr',
    displayName: '法文',
    nativeName: 'Français',
    nllbCode: 'fra_Latn',
    whisperCode: 'fr',
    flag: '🇫🇷',
  ),
  german(
    code: 'de',
    displayName: '德文',
    nativeName: 'Deutsch',
    nllbCode: 'deu_Latn',
    whisperCode: 'de',
    flag: '🇩🇪',
  ),
  russian(
    code: 'ru',
    displayName: '俄文',
    nativeName: 'Русский',
    nllbCode: 'rus_Cyrl',
    whisperCode: 'ru',
    flag: '🇷🇺',
  ),
  spanish(
    code: 'es',
    displayName: '西班牙文',
    nativeName: 'Español',
    nllbCode: 'spa_Latn',
    whisperCode: 'es',
    flag: '🇪🇸',
  ),
  italian(
    code: 'it',
    displayName: '意大利文',
    nativeName: 'Italiano',
    nllbCode: 'ita_Latn',
    whisperCode: 'it',
    flag: '🇮🇹',
  );

  final String code;
  final String displayName;
  final String nativeName;
  final String nllbCode;
  final String whisperCode;
  final String flag;

  const SupportedLanguage({
    required this.code,
    required this.displayName,
    required this.nativeName,
    required this.nllbCode,
    required this.whisperCode,
    required this.flag,
  });

  /// 根据短代码查找语言
  static SupportedLanguage? fromCode(String code) {
    try {
      return SupportedLanguage.values.firstWhere((l) => l.code == code);
    } catch (_) {
      return null;
    }
  }

  /// 根据 NLLB 代码查找语言
  static SupportedLanguage? fromNllbCode(String nllbCode) {
    try {
      return SupportedLanguage.values.firstWhere((l) => l.nllbCode == nllbCode);
    } catch (_) {
      return null;
    }
  }
}

/// 语言代码工具类
class LanguageCodes {
  LanguageCodes._();

  /// 短代码 -> NLLB 代码
  static String getNllbCode(String shortCode) {
    final lang = SupportedLanguage.fromCode(shortCode);
    return lang?.nllbCode ?? 'eng_Latn';
  }

  /// NLLB 代码 -> 短代码
  static String getShortCode(String nllbCode) {
    final lang = SupportedLanguage.fromNllbCode(nllbCode);
    return lang?.code ?? 'en';
  }

  /// 短代码 -> 显示名称
  static String getDisplayName(String shortCode) {
    final lang = SupportedLanguage.fromCode(shortCode);
    return lang?.displayName ?? shortCode;
  }

  /// 短代码 -> 国旗 emoji
  static String getFlag(String shortCode) {
    final lang = SupportedLanguage.fromCode(shortCode);
    return lang?.flag ?? '🏳️';
  }

  /// 短代码 -> Whisper 语言代码
  static String getWhisperCode(String shortCode) {
    final lang = SupportedLanguage.fromCode(shortCode);
    return lang?.whisperCode ?? 'en';
  }

  /// 短代码 -> 原生语言名
  static String getNativeName(String shortCode) {
    final lang = SupportedLanguage.fromCode(shortCode);
    return lang?.nativeName ?? shortCode;
  }

  /// 获取所有支持语言的短代码列表
  static List<String> get allCodes =>
      SupportedLanguage.values.map((l) => l.code).toList();

  /// 获取所有支持语言的 NLLB 代码列表
  static List<String> get allNllbCodes =>
      SupportedLanguage.values.map((l) => l.nllbCode).toList();
}
