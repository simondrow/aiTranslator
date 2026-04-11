Pod::Spec.new do |s|
  s.name             = 'AiFasttext'
  s.version          = '0.1.0'
  s.summary          = 'fastText language detection bridge for AI Translator'
  s.homepage         = 'https://github.com/user/AITranslator'
  s.license          = { :type => 'MIT' }
  s.author           = 'AITranslator'
  s.source           = { :git => '', :tag => s.version.to_s }
  s.platform         = :ios, '15.0'

  s.source_files = [
    'third_party/fastText/src/*.{h,cc}',
    'bridge/fasttext_bridge.{h,cpp}',
  ]
  s.exclude_files = 'third_party/fastText/src/main.cc'
  s.public_header_files = 'bridge/fasttext_bridge.h'

  s.static_framework = true

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) AI_HAS_FASTTEXT=1',
    'HEADER_SEARCH_PATHS' => [
      '"${PODS_TARGET_SRCROOT}/third_party/fastText/src"',
      '"${PODS_TARGET_SRCROOT}/bridge"',
    ].join(' '),
    'OTHER_CPLUSPLUSFLAGS' => '-O3 -funroll-loops',
  }

  s.libraries = 'c++'
  s.requires_arc = false
end
