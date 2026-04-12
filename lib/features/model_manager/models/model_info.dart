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

  /// NLLB ONNX quantized 模型
  /// 来源: HuggingFace Xenova/nllb-200-distilled-600M
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

  /// 需要下载的模型列表
  /// 注意: fastText lid.176.ftz (917KB) 已打包在 assets 中，无需下载
  static List<ModelInfo> get requiredModels => [
        const ModelInfo(
          name: 'Whisper Small',
          url:
              'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin',
          fileName: 'ggml-small.bin',
          sizeInMB: 466,
          modelType: 'whisper',
        ),
        ModelInfo(
          name: 'NLLB-200 ONNX (quantized)',
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
