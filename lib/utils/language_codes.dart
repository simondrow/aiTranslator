/// 语言族分组
/// 用于将检测到的语言映射到用户选择的两种主界面语言之一
enum LanguageFamily {
  /// 东亚: 中文、日语、韩语
  cjk,
  /// 欧洲拉丁/日耳曼/斯拉夫等: 英语、法语、德语、西班牙语、意大利语、俄语等
  european,
}

/// 支持的语言枚举
enum SupportedLanguage {
  chinese(
    code: 'zh',
    displayName: '中文',
    nativeName: '中文',
    nllbCode: 'zho_Hans',
    whisperCode: 'zh',
    flag: '🇨🇳',
    family: LanguageFamily.cjk,
  ),
  english(
    code: 'en',
    displayName: '英文',
    nativeName: 'English',
    nllbCode: 'eng_Latn',
    whisperCode: 'en',
    flag: '🇺🇸',
    family: LanguageFamily.european,
  ),
  japanese(
    code: 'ja',
    displayName: '日文',
    nativeName: '日本語',
    nllbCode: 'jpn_Jpan',
    whisperCode: 'ja',
    flag: '🇯🇵',
    family: LanguageFamily.cjk,
  ),
  korean(
    code: 'ko',
    displayName: '韩文',
    nativeName: '한국어',
    nllbCode: 'kor_Hang',
    whisperCode: 'ko',
    flag: '🇰🇷',
    family: LanguageFamily.cjk,
  ),
  french(
    code: 'fr',
    displayName: '法文',
    nativeName: 'Français',
    nllbCode: 'fra_Latn',
    whisperCode: 'fr',
    flag: '🇫🇷',
    family: LanguageFamily.european,
  ),
  german(
    code: 'de',
    displayName: '德文',
    nativeName: 'Deutsch',
    nllbCode: 'deu_Latn',
    whisperCode: 'de',
    flag: '🇩🇪',
    family: LanguageFamily.european,
  ),
  russian(
    code: 'ru',
    displayName: '俄文',
    nativeName: 'Русский',
    nllbCode: 'rus_Cyrl',
    whisperCode: 'ru',
    flag: '🇷🇺',
    family: LanguageFamily.european,
  ),
  spanish(
    code: 'es',
    displayName: '西班牙文',
    nativeName: 'Español',
    nllbCode: 'spa_Latn',
    whisperCode: 'es',
    flag: '🇪🇸',
    family: LanguageFamily.european,
  ),
  italian(
    code: 'it',
    displayName: '意大利文',
    nativeName: 'Italiano',
    nllbCode: 'ita_Latn',
    whisperCode: 'it',
    flag: '🇮🇹',
    family: LanguageFamily.european,
  );

  final String code;
  final String displayName;
  final String nativeName;
  final String nllbCode;
  final String whisperCode;
  final String flag;
  final LanguageFamily family;

  const SupportedLanguage({
    required this.code,
    required this.displayName,
    required this.nativeName,
    required this.nllbCode,
    required this.whisperCode,
    required this.flag,
    required this.family,
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

  /// 获取语言所属族
  static LanguageFamily getFamily(String shortCode) {
    final lang = SupportedLanguage.fromCode(shortCode);
    return lang?.family ?? _inferFamilyFromCode(shortCode);
  }

  /// 对于 fastText 检测到但不在 SupportedLanguage 枚举中的语言，
  /// 通过 ISO 639-1 代码推断其所属语言族。
  ///
  /// 规则:
  ///   CJK 族: zh, ja, ko, yue(粤语), wuu(吴语), hak(客家话), nan(闽南语)
  ///   其余所有: 归为 european (包括拉丁系、日耳曼系、斯拉夫系、阿拉伯语、
  ///           印地语、越南语、泰语等——只要不是 CJK 就归对方)
  ///
  /// 这是一个实用近似: 在实际翻译场景中，用户设置了"我方-中文/对方-英文"，
  /// 如果输入了法语，意图几乎总是"翻译成中文"，而非"翻译成法语"。
  static LanguageFamily _inferFamilyFromCode(String code) {
    const cjkCodes = {'zh', 'ja', 'ko', 'yue', 'wuu', 'hak', 'nan', 'lzh'};
    return cjkCodes.contains(code) ? LanguageFamily.cjk : LanguageFamily.european;
  }

  /// 判断检测到的语言 [detectedCode] 与界面语言 [uiLangCode] 是否属于同族。
  static bool isSameFamily(String detectedCode, String uiLangCode) {
    return getFamily(detectedCode) == getFamily(uiLangCode);
  }

  /// 获取所有支持语言的短代码列表
  static List<String> get allCodes =>
      SupportedLanguage.values.map((l) => l.code).toList();

  /// 获取所有支持语言的 NLLB 代码列表
  static List<String> get allNllbCodes =>
      SupportedLanguage.values.map((l) => l.nllbCode).toList();
}
