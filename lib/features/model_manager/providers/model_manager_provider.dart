import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models/model_info.dart';

/// 模型管理状态
class ModelManagerState {
  final List<ModelInfo> models;
  final bool isDownloading;
  final String? errorMessage;
  final String? downloadingModelName;

  const ModelManagerState({
    this.models = const [],
    this.isDownloading = false,
    this.errorMessage,
    this.downloadingModelName,
  });

  ModelManagerState copyWith({
    List<ModelInfo>? models,
    bool? isDownloading,
    String? errorMessage,
    String? downloadingModelName,
  }) {
    return ModelManagerState(
      models: models ?? this.models,
      isDownloading: isDownloading ?? this.isDownloading,
      errorMessage: errorMessage,
      downloadingModelName: downloadingModelName,
    );
  }

  bool get allModelsReady => models.every((m) => m.isDownloaded);

  bool get isNllbReady =>
      models.any((m) => m.modelType == ModelInfo.nllbModelType && m.isDownloaded);

  bool get isWhisperReady =>
      models.any((m) => m.modelType == ModelInfo.whisperModelType && m.isDownloaded);
}

class ModelManagerNotifier extends StateNotifier<ModelManagerState> {
  final Dio _dio;
  CancelToken? _cancelToken;
  Completer<void>? _initCompleter;

  ModelManagerNotifier()
      : _dio = Dio(),
        super(const ModelManagerState()) {
    _initCompleter = Completer<void>();
    Future.microtask(() => _initModels());
  }

  /// 等待模型列表初始化完成（可多次调用，安全幂等）
  Future<void> ensureInitialized() async {
    if (_initCompleter != null) {
      await _initCompleter!.future;
    }
  }

  Future<void> _initModels() async {
    try {
      final modelsDir = await _getModelsDirectory();
      final List<ModelInfo> checkedModels = [];

      for (final model in ModelInfo.requiredModels) {
        bool exists;

        if (model.modelType == ModelInfo.nllbModelType) {
          exists = await _isNllbModelComplete(modelsDir.path);
        } else if (model.modelType == ModelInfo.whisperModelType) {
          final file = File(
              '${modelsDir.path}/${ModelInfo.whisperModelDirName}/${model.fileName}');
          exists = await file.exists();
        } else {
          final file = File('${modelsDir.path}/${model.fileName}');
          exists = await file.exists();
        }

        checkedModels.add(model.copyWith(
          isDownloaded: exists,
          downloadProgress: exists ? 1.0 : 0.0,
        ));
      }

      if (mounted) {
        state = state.copyWith(models: checkedModels);
      }
    } finally {
      _initCompleter?.complete();
    }
  }

  Future<bool> _isNllbModelComplete(String modelsBasePath) async {
    final nllbDir = '$modelsBasePath/${ModelInfo.nllbModelDirName}';
    for (final fileInfo in ModelInfo.nllbModelFiles) {
      final file = File('$nllbDir/${fileInfo.name}');
      if (!await file.exists()) return false;
    }
    return true;
  }

  Future<Directory> _getModelsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir;
  }

  Future<String> getModelPath(String fileName) async {
    final modelsDir = await _getModelsDirectory();
    return '${modelsDir.path}/$fileName';
  }

  Future<String> getNllbModelDir() async {
    final modelsDir = await _getModelsDirectory();
    return '${modelsDir.path}/${ModelInfo.nllbModelDirName}';
  }

  Future<String> getWhisperModelPath() async {
    final modelsDir = await _getModelsDirectory();
    return '${modelsDir.path}/${ModelInfo.whisperModelDirName}/${ModelInfo.whisperModelFileName}';
  }

  bool isModelReady() => state.allModelsReady;

  Future<void> downloadModel(ModelInfo modelInfo) async {
    if (!mounted) return;
    state = state.copyWith(
      isDownloading: true,
      errorMessage: null,
      downloadingModelName: modelInfo.name,
    );
    _cancelToken = CancelToken();

    try {
      if (modelInfo.modelType == ModelInfo.nllbModelType) {
        await _downloadNllbModel(modelInfo);
      } else if (modelInfo.modelType == ModelInfo.whisperModelType) {
        await _downloadWhisperModel(modelInfo);
      } else {
        await _downloadSingleFile(modelInfo);
      }
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        debugPrint('[ModelManager] 下载已取消: ${modelInfo.name}');
      } else {
        if (mounted) {
          state = state.copyWith(
            isDownloading: false,
            errorMessage: '下载失败: $e',
            downloadingModelName: null,
          );
        }
        debugPrint('模型下载失败: $e');
        rethrow;
      }
    }
  }

  Future<void> _downloadSingleFile(ModelInfo modelInfo) async {
    final modelsDir = await _getModelsDirectory();
    final savePath = '${modelsDir.path}/${modelInfo.fileName}';

    await _dio.download(
      modelInfo.url,
      savePath,
      cancelToken: _cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0 && mounted) {
          _updateModelProgress(modelInfo.fileName, received / total);
        }
      },
    );

    if (mounted) {
      _updateModelState(modelInfo.fileName, isDownloaded: true, progress: 1.0);
      state = state.copyWith(isDownloading: false, downloadingModelName: null);
    }
  }

  Future<void> _downloadWhisperModel(ModelInfo modelInfo) async {
    final modelsDir = await _getModelsDirectory();
    final whisperDir =
        Directory('${modelsDir.path}/${ModelInfo.whisperModelDirName}');
    if (!await whisperDir.exists()) {
      await whisperDir.create(recursive: true);
    }

    final savePath = '${whisperDir.path}/${modelInfo.fileName}';

    if (File(savePath).existsSync()) {
      if (mounted) {
        _updateModelState(modelInfo.fileName,
            isDownloaded: true, progress: 1.0);
        state =
            state.copyWith(isDownloading: false, downloadingModelName: null);
      }
      return;
    }

    debugPrint('[ModelManager] 下载 Whisper: ${modelInfo.fileName}');

    await _dio.download(
      modelInfo.url,
      savePath,
      cancelToken: _cancelToken,
      onReceiveProgress: (received, total) {
        if (total > 0 && mounted) {
          _updateModelProgress(modelInfo.fileName, received / total);
        }
      },
    );

    if (mounted) {
      _updateModelState(modelInfo.fileName,
          isDownloaded: true, progress: 1.0);
      state = state.copyWith(isDownloading: false, downloadingModelName: null);
    }
  }

  Future<void> _downloadNllbModel(ModelInfo modelInfo) async {
    final modelsDir = await _getModelsDirectory();
    final nllbDir =
        Directory('${modelsDir.path}/${ModelInfo.nllbModelDirName}');
    if (!await nllbDir.exists()) {
      await nllbDir.create(recursive: true);
    }

    final files = ModelInfo.nllbModelFiles;
    final totalSize = files.fold<double>(0, (s, f) => s + f.sizeInMB);
    double downloadedSize = 0;

    for (int i = 0; i < files.length; i++) {
      final fileInfo = files[i];
      final savePath = '${nllbDir.path}/${fileInfo.name}';

      if (File(savePath).existsSync()) {
        downloadedSize += fileInfo.sizeInMB;
        if (mounted) {
          _updateModelProgress(modelInfo.fileName, downloadedSize / totalSize);
        }
        continue;
      }

      debugPrint(
          '[ModelManager] 下载 NLLB ${i + 1}/${files.length}: ${fileInfo.name}');

      final baseDownloaded = downloadedSize;
      await _dio.download(
        fileInfo.url,
        savePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            final fileProgress = received / total;
            final overallProgress =
                (baseDownloaded + fileInfo.sizeInMB * fileProgress) / totalSize;
            _updateModelProgress(modelInfo.fileName, overallProgress);
          }
        },
      );

      downloadedSize += fileInfo.sizeInMB;
    }

    if (mounted) {
      _updateModelState(modelInfo.fileName,
          isDownloaded: true, progress: 1.0);
      state = state.copyWith(isDownloading: false, downloadingModelName: null);
    }
  }

  void cancelDownload() {
    _cancelToken?.cancel('用户取消');
    if (mounted) {
      state = state.copyWith(isDownloading: false, downloadingModelName: null);
    }
  }

  Future<void> downloadAllModels() async {
    await ensureInitialized();
    for (final model in state.models) {
      if (!model.isDownloaded) {
        await downloadModel(model);
      }
    }
  }

  Future<void> downloadNllbIfNeeded() async {
    await ensureInitialized();
    final nllbModel = state.models.firstWhere(
      (m) => m.modelType == ModelInfo.nllbModelType,
      orElse: () => ModelInfo.requiredModels.last,
    );
    if (!nllbModel.isDownloaded) {
      await downloadModel(nllbModel);
    }
  }

  Future<void> downloadWhisperIfNeeded() async {
    await ensureInitialized();
    final whisperModel = state.models.firstWhere(
      (m) => m.modelType == ModelInfo.whisperModelType,
      orElse: () => ModelInfo.requiredModels.first,
    );
    if (!whisperModel.isDownloaded) {
      await downloadModel(whisperModel);
    }
  }

  void _updateModelProgress(String fileName, double progress) {
    if (!mounted) return;
    final updatedModels = state.models.map((m) {
      if (m.fileName == fileName) {
        return m.copyWith(downloadProgress: progress);
      }
      return m;
    }).toList();
    state = state.copyWith(models: updatedModels);
  }

  void _updateModelState(
    String fileName, {
    required bool isDownloaded,
    required double progress,
  }) {
    if (!mounted) return;
    final updatedModels = state.models.map((m) {
      if (m.fileName == fileName) {
        return m.copyWith(
          isDownloaded: isDownloaded,
          downloadProgress: progress,
        );
      }
      return m;
    }).toList();
    state = state.copyWith(models: updatedModels);
  }
}

final modelManagerProvider =
    StateNotifierProvider<ModelManagerNotifier, ModelManagerState>((ref) {
  return ModelManagerNotifier();
});
