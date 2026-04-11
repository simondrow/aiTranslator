/// 模型信息
class ModelInfo {
  final String name;
  final String url;
  final String fileName;
  final double sizeInMB;
  final bool isDownloaded;
  final double downloadProgress;

  const ModelInfo({
    required this.name,
    required this.url,
    required this.fileName,
    required this.sizeInMB,
    this.isDownloaded = false,
    this.downloadProgress = 0.0,
  });

  ModelInfo copyWith({
    String? name,
    String? url,
    String? fileName,
    double? sizeInMB,
    bool? isDownloaded,
    double? downloadProgress,
  }) {
    return ModelInfo(
      name: name ?? this.name,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      sizeInMB: sizeInMB ?? this.sizeInMB,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      downloadProgress: downloadProgress ?? this.downloadProgress,
    );
  }

  /// 需要下载的模型列表
  /// 注意: fastText lid.176.ftz (917KB) 已打包在 assets 中，无需下载
  static List<ModelInfo> get requiredModels => [
        const ModelInfo(
          name: 'Whisper Small',
          url:
              'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin',
          fileName: 'ggml-small.bin',
          sizeInMB: 466,
        ),
        const ModelInfo(
          name: 'NLLB-200-distilled-600M',
          url:
              'https://huggingface.co/JustFrederik/nllb-200-distilled-600M-ct2-float16/resolve/main/model.bin',
          fileName: 'nllb-200-distilled-600M.bin',
          sizeInMB: 600,
        ),
      ];
}
