/// 模型信息
class ModelInfo {
  final String name;
  final String url;
  final String fileName;
  final double sizeInMB;
  final bool isDownloaded;
  final double downloadProgress;
  /// 模型类型标识，用于区分不同的模型
  final String modelType;

  const ModelInfo({
    required this.name,
    required this.url,
    required this.fileName,
    required this.sizeInMB,
    this.isDownloaded = false,
    this.downloadProgress = 0.0,
    this.modelType = 'generic',
  });

  ModelInfo copyWith({
    String? name,
    String? url,
    String? fileName,
    double? sizeInMB,
    bool? isDownloaded,
    double? downloadProgress,
    String? modelType,
  }) {
    return ModelInfo(
      name: name ?? this.name,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      sizeInMB: sizeInMB ?? this.sizeInMB,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      downloadProgress: downloadProgress ?? this.downloadProgress,
      modelType: modelType ?? this.modelType,
    );
  }

  // =============================================================
  // NLLB ONNX quantized 翻译模型
  // 来源: HuggingFace Xenova/nllb-200-distilled-600M
  // =============================================================
  static const String nllbModelType = 'nllb-onnx';
  static const String nllbModelDirName = 'nllb-onnx';

  /// NLLB 模型需要下载的所有文件
  static List<NllbModelFile> get nllbModelFiles => const [
        NllbModelFile(
          name: 'encoder_model_quantized.onnx',
          url: 'https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/main/onnx/encoder_model_quantized.onnx',
          sizeInMB: 419,
        ),
        NllbModelFile(
          name: 'decoder_model_merged_quantized.onnx',
          url: 'https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/main/onnx/decoder_model_merged_quantized.onnx',
          sizeInMB: 476,
        ),
        NllbModelFile(
          name: 'tokenizer.json',
          url: 'https://huggingface.co/Xenova/nllb-200-distilled-600M/resolve/main/tokenizer.json',
          sizeInMB: 17,
        ),
      ];

  /// NLLB 模型总大小 (MB)
  static double get nllbTotalSizeMB =>
      nllbModelFiles.fold(0, (sum, f) => sum + f.sizeInMB);

  // =============================================================
  // SenseVoice 语音识别模型 (替代 Whisper)
  // 来源: sherpa-onnx 预转换模型
  // Non-autoregressive，推理速度极快（<1s per segment on mobile）
  // 支持: 中文、英文、日文、韩文、粤语
  // =============================================================
  static const String senseVoiceModelType = 'sensevoice';
  static const String senseVoiceModelDirName = 'sensevoice';

  /// SenseVoice 模型需要下载的文件
  static List<SenseVoiceModelFile> get senseVoiceModelFiles => const [
        SenseVoiceModelFile(
          name: 'model.int8.onnx',
          url: 'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/model.int8.onnx',
          sizeInMB: 228,
        ),
        SenseVoiceModelFile(
          name: 'tokens.txt',
          url: 'https://huggingface.co/csukuangfj/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17/resolve/main/tokens.txt',
          sizeInMB: 1,
        ),
      ];

  /// SenseVoice 模型总大小 (MB)
  static double get senseVoiceTotalSizeMB =>
      senseVoiceModelFiles.fold(0.0, (sum, f) => sum + f.sizeInMB);

  // =============================================================
  // [DEPRECATED] Whisper 语音识别模型 — 已被 SenseVoice 替代
  // 保留常量以兼容迁移
  // =============================================================
  static const String whisperModelType = 'whisper';
  static const String whisperModelDirName = 'whisper';
  static const String whisperModelFileName = 'ggml-base.bin';

  /// 需要下载的模型列表
  /// 注意: fastText lid.176.ftz (917KB) 已打包在 assets 中，无需下载
  static List<ModelInfo> get requiredModels => [
        ModelInfo(
          name: 'SenseVoice (语音识别)',
          url: '', // 多文件下载，url 在 senseVoiceModelFiles 中
          fileName: senseVoiceModelDirName,
          sizeInMB: senseVoiceTotalSizeMB,
          modelType: senseVoiceModelType,
        ),
        ModelInfo(
          name: 'NLLB-200 ONNX (翻译)',
          url: '', // 多文件下载，url 在 nllbModelFiles 中
          fileName: nllbModelDirName,
          sizeInMB: nllbTotalSizeMB,
          modelType: nllbModelType,
        ),
      ];
}

/// NLLB 模型单个文件信息
class NllbModelFile {
  final String name;
  final String url;
  final double sizeInMB;

  const NllbModelFile({
    required this.name,
    required this.url,
    required this.sizeInMB,
  });
}

/// SenseVoice 模型单个文件信息
class SenseVoiceModelFile {
  final String name;
  final String url;
  final double sizeInMB;

  const SenseVoiceModelFile({
    required this.name,
    required this.url,
    required this.sizeInMB,
  });
}
