Pod::Spec.new do |s|
  s.name             = 'AiWhisper'
  s.version          = '0.1.0'
  s.summary          = 'whisper.cpp speech recognition bridge for AI Translator'
  s.homepage         = 'https://github.com/simondrow/aiTranslator'
  s.license          = { :type => 'MIT' }
  s.author           = 'AITranslator'
  s.source           = { :git => '', :tag => s.version.to_s }
  s.platform         = :ios, '15.0'

  whisper_dir = 'third_party/whisper.cpp'

  # ---- Source files ----
  # Bridge
  s.source_files = [
    'bridge/whisper_bridge.{h,cpp}',

    # whisper.cpp core
    "#{whisper_dir}/src/whisper.cpp",
    "#{whisper_dir}/src/whisper-arch.h",
    "#{whisper_dir}/include/whisper.h",

    # ggml core
    "#{whisper_dir}/ggml/src/ggml.c",
    "#{whisper_dir}/ggml/src/ggml.cpp",
    "#{whisper_dir}/ggml/src/ggml-alloc.c",
    "#{whisper_dir}/ggml/src/ggml-backend.cpp",
    "#{whisper_dir}/ggml/src/ggml-backend-reg.cpp",
    "#{whisper_dir}/ggml/src/ggml-backend-dl.h",
    "#{whisper_dir}/ggml/src/ggml-quants.c",
    "#{whisper_dir}/ggml/src/ggml-opt.cpp",
    "#{whisper_dir}/ggml/src/ggml-threading.cpp",
    "#{whisper_dir}/ggml/src/gguf.cpp",
    "#{whisper_dir}/ggml/src/ggml-impl.h",
    "#{whisper_dir}/ggml/src/ggml-common.h",
    "#{whisper_dir}/ggml/src/ggml-backend-impl.h",

    # ggml-cpu backend
    "#{whisper_dir}/ggml/src/ggml-cpu/ggml-cpu.c",
    "#{whisper_dir}/ggml/src/ggml-cpu/ggml-cpu.cpp",
    "#{whisper_dir}/ggml/src/ggml-cpu/ggml-cpu-impl.h",
    "#{whisper_dir}/ggml/src/ggml-cpu/common.h",
    "#{whisper_dir}/ggml/src/ggml-cpu/quants.c",
    "#{whisper_dir}/ggml/src/ggml-cpu/quants.h",
    "#{whisper_dir}/ggml/src/ggml-cpu/binary-ops.cpp",
    "#{whisper_dir}/ggml/src/ggml-cpu/binary-ops.h",
    "#{whisper_dir}/ggml/src/ggml-cpu/unary-ops.cpp",
    "#{whisper_dir}/ggml/src/ggml-cpu/unary-ops.h",
    "#{whisper_dir}/ggml/src/ggml-cpu/ops.cpp",
    "#{whisper_dir}/ggml/src/ggml-cpu/ops.h",
    "#{whisper_dir}/ggml/src/ggml-cpu/vec.cpp",
    "#{whisper_dir}/ggml/src/ggml-cpu/vec.h",
    "#{whisper_dir}/ggml/src/ggml-cpu/traits.cpp",
    "#{whisper_dir}/ggml/src/ggml-cpu/traits.h",
    "#{whisper_dir}/ggml/src/ggml-cpu/repack.cpp",
    "#{whisper_dir}/ggml/src/ggml-cpu/repack.h",
    "#{whisper_dir}/ggml/src/ggml-cpu/hbm.cpp",
    "#{whisper_dir}/ggml/src/ggml-cpu/hbm.h",
    "#{whisper_dir}/ggml/src/ggml-cpu/simd-mappings.h",
    "#{whisper_dir}/ggml/src/ggml-cpu/arch-fallback.h",

    # ggml-cpu ARM (NEON) architecture-specific
    "#{whisper_dir}/ggml/src/ggml-cpu/arch/arm/*.{c,cpp,h}",

    # ggml-cpu llamafile SGEMM
    "#{whisper_dir}/ggml/src/ggml-cpu/llamafile/sgemm.cpp",
    "#{whisper_dir}/ggml/src/ggml-cpu/llamafile/*.h",

    # ggml-metal backend
    "#{whisper_dir}/ggml/src/ggml-metal/ggml-metal.cpp",
    "#{whisper_dir}/ggml/src/ggml-metal/ggml-metal-common.cpp",
    "#{whisper_dir}/ggml/src/ggml-metal/ggml-metal-common.h",
    "#{whisper_dir}/ggml/src/ggml-metal/ggml-metal-context.m",
    "#{whisper_dir}/ggml/src/ggml-metal/ggml-metal-context.h",
    "#{whisper_dir}/ggml/src/ggml-metal/ggml-metal-device.cpp",
    "#{whisper_dir}/ggml/src/ggml-metal/ggml-metal-device.m",
    "#{whisper_dir}/ggml/src/ggml-metal/ggml-metal-device.h",
    "#{whisper_dir}/ggml/src/ggml-metal/ggml-metal-ops.cpp",
    "#{whisper_dir}/ggml/src/ggml-metal/ggml-metal-ops.h",
    "#{whisper_dir}/ggml/src/ggml-metal/ggml-metal-impl.h",

    # ggml public headers
    "#{whisper_dir}/ggml/include/*.h",
  ]

  # Metal shader
  s.resources = [
    "#{whisper_dir}/ggml/src/ggml-metal/ggml-metal.metal",
  ]

  s.public_header_files = 'bridge/whisper_bridge.h'

  # Exclude non-ARM architectures and unneeded backends
  s.exclude_files = [
    "#{whisper_dir}/ggml/src/ggml-cpu/arch/x86/**",
    "#{whisper_dir}/ggml/src/ggml-cpu/arch/riscv/**",
    "#{whisper_dir}/ggml/src/ggml-cpu/arch/s390/**",
    "#{whisper_dir}/ggml/src/ggml-cpu/arch/wasm/**",
    "#{whisper_dir}/ggml/src/ggml-cpu/arch/loongarch/**",
    "#{whisper_dir}/ggml/src/ggml-cpu/amx/**",
    "#{whisper_dir}/ggml/src/ggml-cpu/spacemit/**",
    "#{whisper_dir}/ggml/src/ggml-cpu/kleidiai/**",
  ]

  s.static_framework = true

  s.pod_target_xcconfig = {
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'GCC_PREPROCESSOR_DEFINITIONS' => [
      '$(inherited)',
      'AI_HAS_WHISPER=1',
      'GGML_USE_METAL=1',
      'GGML_METAL_EMBED_LIBRARY=0',
      'GGML_USE_CPU=1',
      'NDEBUG=1',
      'ACCELERATE_NEW_LAPACK=1',
      '_DARWIN_C_SOURCE=1',
    ].join(' '),
    'HEADER_SEARCH_PATHS' => [
      '"${PODS_TARGET_SRCROOT}/bridge"',
      '"${PODS_TARGET_SRCROOT}/third_party/whisper.cpp/include"',
      '"${PODS_TARGET_SRCROOT}/third_party/whisper.cpp/src"',
      '"${PODS_TARGET_SRCROOT}/third_party/whisper.cpp/ggml/include"',
      '"${PODS_TARGET_SRCROOT}/third_party/whisper.cpp/ggml/src"',
      '"${PODS_TARGET_SRCROOT}/third_party/whisper.cpp/ggml/src/ggml-cpu"',
      '"${PODS_TARGET_SRCROOT}/third_party/whisper.cpp/ggml/src/ggml-cpu/arch"',
      '"${PODS_TARGET_SRCROOT}/third_party/whisper.cpp/ggml/src/ggml-metal"',
      '"${PODS_TARGET_SRCROOT}/third_party/whisper.cpp/ggml/src/ggml-cpu/llamafile"',
    ].join(' '),
    'OTHER_CFLAGS' => '-O3 -DNDEBUG'\"1.8.4\"\'',
    'OTHER_CPLUSPLUSFLAGS' => '-O3 -DNDEBUG -std=c++17',
    'MTL_FAST_MATH' => 'YES',
  }

  s.frameworks = ['Metal', 'MetalKit', 'Accelerate', 'Foundation', 'MetalPerformanceShaders']
  s.libraries = 'c++'
  s.requires_arc = false
end
