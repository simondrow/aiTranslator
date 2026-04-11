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

  const ModelManagerState({
    this.models = const [],
    this.isDownloading = false,
    this.errorMessage,
  });

  ModelManagerState copyWith({
    List<ModelInfo>? models,
    bool? isDownloading,
    String? errorMessage,
  }) {
    return ModelManagerState(
      models: models ?? this.models,
      isDownloading: isDownloading ?? this.isDownloading,
      errorMessage: errorMessage,
    );
  }

  /// 所有模型是否都已下载
  bool get allModelsReady => models.every((m) => m.isDownloaded);
}

/// 模型管理器
class ModelManagerNotifier extends StateNotifier<ModelManagerState> {
  final Dio _dio;

  ModelManagerNotifier()
      : _dio = Dio(),
        super(const ModelManagerState()) {
    _initModels();
  }

  /// 初始化模型列表，并检查本地是否已存在
  Future<void> _initModels() async {
    final modelsDir = await _getModelsDirectory();
    final List<ModelInfo> checkedModels = [];

    for (final model in ModelInfo.requiredModels) {
      final file = File('${modelsDir.path}/${model.fileName}');
      final exists = await file.exists();
      checkedModels.add(model.copyWith(
        isDownloaded: exists,
        downloadProgress: exists ? 1.0 : 0.0,
      ));
    }

    state = state.copyWith(models: checkedModels);
  }

  /// 获取模型存储目录
  Future<Directory> _getModelsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelsDir = Directory('${appDir.path}/models');
    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }
    return modelsDir;
  }

  /// 获取指定模型的本地路径
  Future<String> getModelPath(String fileName) async {
    final modelsDir = await _getModelsDirectory();
    return '${modelsDir.path}/$fileName';
  }

  /// 所有模型是否就绪
  bool isModelReady() {
    return state.allModelsReady;
  }

  /// 下载指定模型
  Future<void> downloadModel(ModelInfo modelInfo) async {
    state = state.copyWith(isDownloading: true, errorMessage: null);

    try {
      final modelsDir = await _getModelsDirectory();
      final savePath = '${modelsDir.path}/${modelInfo.fileName}';

      await _dio.download(
        modelInfo.url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            _updateModelProgress(modelInfo.fileName, progress);
          }
        },
      );

      // 标记下载完成
      _updateModelState(modelInfo.fileName, isDownloaded: true, progress: 1.0);
      state = state.copyWith(isDownloading: false);
    } catch (e) {
      state = state.copyWith(
        isDownloading: false,
        errorMessage: '下载失败: ${modelInfo.name} - $e',
      );
      debugPrint('模型下载失败: $e');
    }
  }

  /// 下载所有未下载的模型
  Future<void> downloadAllModels() async {
    for (final model in state.models) {
      if (!model.isDownloaded) {
        await downloadModel(model);
      }
    }
  }

  void _updateModelProgress(String fileName, double progress) {
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

/// Provider
final modelManagerProvider =
    StateNotifierProvider<ModelManagerNotifier, ModelManagerState>((ref) {
  return ModelManagerNotifier();
});
