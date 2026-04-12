Pod::Spec.new do |s|
  s.name             = 'AiNllb'
  s.version          = '0.1.0'
  s.summary          = 'NLLB-200 CTranslate2 translation bridge for AI Translator'
  s.homepage         = 'https://github.com/user/AITranslator'
  s.license          = { :type => 'MIT' }
  s.author           = 'AITranslator'
  s.source           = { :git => '', :tag => s.version.to_s }
  s.platform         = :ios, '15.0'

  # Bridge source (C++ with optional CTranslate2/SentencePiece)
  s.source_files = [
    'bridge/nllb_bridge.{h,cpp}',
  ]
  s.public_header_files = 'bridge/nllb_bridge.h'

  s.static_framework = true

  # 注意: 当 CTranslate2 和 SentencePiece 库编译好后，
  # 需要在此添加 vendored_libraries 或 vendored_frameworks
  # 并开启 AI_HAS_CTRANSLATE2 宏定义
  #
  # 暂时编译为 stub 模式（不定义 AI_HAS_CTRANSLATE2）
  # 真实翻译通过 Dart 层 stub 提供占位结果

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    # 'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) AI_HAS_CTRANSLATE2=1',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/bridge"',
  }

  s.libraries = 'c++'
  s.requires_arc = false
end
