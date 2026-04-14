/// 语言族分组
/// 用于将检测到的语言映射到用户选择的两种主界面语言之一
enum LanguageFamily {
  /// 东亚: 中文、日语、韩语
  cjk,
  /// 西方/其他: 英语及其他非 CJK 语系
  western,
}

/// 支持的语言枚举
/// 仅保留 SenseVoice ASR 和 HY-MT 翻译均能良好支持的 4 种语言
enum SupportedLanguage {
  chinese(
    code: 'zh',
    displayName: '中文',
    nativeName: '中文',
    flag: '🇨🇳',
    family: LanguageFamily.cjk,
  ),
  english(
    code: 'en',
    displayName: '英文',
    nativeName: 'English',
    flag: '🇺🇸',
    family: LanguageFamily.western,
  ),
  japanese(
    code: 'ja',
    displayName: '日文',
    nativeName: '日本語',
    flag: '🇯🇵',
    family: LanguageFamily.cjk,
  ),
  korean(
    code: 'ko',
    displayName: '韩文',
    nativeName: '한국어',
    flag: '🇰🇷',
    family: LanguageFamily.cjk,
  );

  final String code;
  final String displayName;
  final String nativeName;
  final String flag;
  final LanguageFamily family;

  const SupportedLanguage({
    required this.code,
    required this.displayName,
    required this.nativeName,
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
}

/// 语言代码工具类
class LanguageCodes {
  LanguageCodes._();

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
  ///   其余所有: 归为 western
  static LanguageFamily _inferFamilyFromCode(String code) {
    const cjkCodes = {'zh', 'ja', 'ko', 'yue', 'wuu', 'hak', 'nan', 'lzh'};
    return cjkCodes.contains(code) ? LanguageFamily.cjk : LanguageFamily.western;
  }

  /// 判断检测到的语言 [detectedCode] 与界面语言 [uiLangCode] 是否属于同族。
  static bool isSameFamily(String detectedCode, String uiLangCode) {
    return getFamily(detectedCode) == getFamily(uiLangCode);
  }

  /// 获取所有支持语言的短代码列表
  static List<String> get allCodes =>
      SupportedLanguage.values.map((l) => l.code).toList();
}
