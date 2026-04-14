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

  // ==============================================================
  // HY-MT1.5-1.8B GGUF 翻译模型
  // 来源: Tencent HunyuanTranslation
  // Q4_K_M 量化, ~1.13GB, 支持中/英/日/韩
  // 通过 llama.cpp (flutter_llama) 推理
  // ==============================================================
  static const String hymtModelType = 'hymt';
  static const String hymtModelDirName = 'hymt';
  static const String hymtModelFileName = 'HY-MT1.5-1.8B-Q4_K_M.gguf';

  /// HY-MT 模型下载文件列表 (单文件)
  static List<HymtModelFile> get hymtModelFiles => const [
        HymtModelFile(
          name: 'HY-MT1.5-1.8B-Q4_K_M.gguf',
          url: 'https://huggingface.co/tencent/HY-MT1.5-1.8B-GGUF/resolve/main/HY-MT1.5-1.8B-Q4_K_M.gguf',
          sizeInMB: 1157,
        ),
      ];

  /// HY-MT 模型总大小 (MB)
  static double get hymtTotalSizeMB =>
      hymtModelFiles.fold(0.0, (sum, f) => sum + f.sizeInMB);

  // ==============================================================
  // SenseVoice 语音识别模型
  // 来源: sherpa-onnx 预转换模型
  // Non-autoregressive，推理速度极快（<1s per segment on mobile）
  // 支持: 中文、英文、日文、韩文、粤语
  // ==============================================================
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

  /// 需要下载的模型列表
  /// 注意: fastText lid.176.ftz (917KB) 已打包在 assets 中，无霁下载
  static List<ModelInfo> get requiredModels => [
        ModelInfo(
          name: 'SenseVoice (语音识别)',
          url: '', // 多文件下载，url 在 senseVoiceModelFiles 中
          fileName: senseVoiceModelDirName,
          sizeInMB: senseVoiceTotalSizeMB,
          modelType: senseVoiceModelType,
        ),
        ModelInfo(
          name: 'HY-MT1.5 (翻译)',
          url: '', // 多文件下载，url 在 hymtModelFiles 中
          fileName: hymtModelDirName,
          sizeInMB: hymtTotalSizeMB,
          modelType: hymtModelType,
        ),
      ];
}

/// HY-MT 模型单个文件信息
class HymtModelFile {
  final String name;
  final String url;
  final double sizeInMB;

  const HymtModelFile({
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
