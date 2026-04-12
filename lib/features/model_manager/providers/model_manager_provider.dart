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
}

class ModelManagerNotifier extends StateNotifier<ModelManagerState> {
  final Dio _dio;
  CancelToken? _cancelToken;
  bool _initialized = false;

  ModelManagerNotifier()
      : _dio = Dio(),
        super(const ModelManagerState()) {
    // 延迟初始化，避免在 widget build 期间修改 provider state
    Future.microtask(() => _initModels());
  }

  Future<void> _initModels() async {
    if (_initialized) return;
    _initialized = true;

    final modelsDir = await _getModelsDirectory();
    final List<ModelInfo> checkedModels = [];

    for (final model in ModelInfo.requiredModels) {
      bool exists;

      if (model.modelType == ModelInfo.nllbModelType) {
        exists = await _isNllbModelComplete(modelsDir.path);
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

  Future<void> _downloadNllbModel(ModelInfo modelInfo) async {
    final modelsDir = await _getModelsDirectory();
    final nllbDir = Directory('${modelsDir.path}/${ModelInfo.nllbModelDirName}');
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

      debugPrint('[ModelManager] 下载 NLLB ${i + 1}/${files.length}: ${fileInfo.name}');

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
      _updateModelState(modelInfo.fileName, isDownloaded: true, progress: 1.0);
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
    for (final model in state.models) {
      if (!model.isDownloaded) {
        await downloadModel(model);
      }
    }
  }

  Future<void> downloadNllbIfNeeded() async {
    final nllbModel = state.models.firstWhere(
      (m) => m.modelType == ModelInfo.nllbModelType,
      orElse: () => ModelInfo.requiredModels.last,
    );
    if (!nllbModel.isDownloaded) {
      await downloadModel(nllbModel);
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
