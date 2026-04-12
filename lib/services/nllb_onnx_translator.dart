import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:onnxruntime/onnxruntime.dart';

/// NLLB ONNX 翻译器
/// 使用 encoder_model_quantized.onnx + decoder_model_merged_quantized.onnx
/// 实现离线翻译（encoder-decoder 自回归推理）
///
/// 词表和分词来自 HuggingFace tokenizer.json (BPE)
class NllbOnnxTranslator {
  OrtSession? _encoderSession;
  OrtSession? _decoderSession;

  /// BPE 词表: token string -> id
  Map<String, int>? _vocab;
  /// 反向词表: id -> token string
  Map<int, String>? _vocabReverse;
  /// BPE merge 规则 (pair -> priority, 越小越优先)
  Map<String, int>? _merges;
  /// 语言 token -> id
  Map<String, int>? _langTokenIds;

  bool _isReady = false;
  bool get isReady => _isReady;

  // 特殊 token IDs (从 tokenizer.json added_tokens 读取, 以下为默认值)
  int _padId = 1;
  int _eosId = 2;
  int _unkId = 3;

  /// 初始化模型
  /// [modelDir] 包含以下文件的目录:
  ///   - encoder_model_quantized.onnx
  ///   - decoder_model_merged_quantized.onnx
  ///   - tokenizer.json
  Future<void> initialize(String modelDir) async {
    try {
      OrtEnv.instance.init();

      final encoderPath = '$modelDir/encoder_model_quantized.onnx';
      final decoderPath = '$modelDir/decoder_model_merged_quantized.onnx';
      final tokenizerPath = '$modelDir/tokenizer.json';

      // 检查必要文件
      for (final path in [encoderPath, decoderPath, tokenizerPath]) {
        if (!File(path).existsSync()) {
          debugPrint('[NllbOnnx] 文件未找到: $path');
          return;
        }
      }

      // 加载 tokenizer
      await _loadTokenizer(tokenizerPath);
      if (_vocab == null || _merges == null) {
        debugPrint('[NllbOnnx] tokenizer 加载失败');
        return;
      }

      // 创建 ONNX sessions
      final sessionOptions = OrtSessionOptions();
      sessionOptions.setInterOpNumThreads(1);
      sessionOptions.setIntraOpNumThreads(2);

      debugPrint('[NllbOnnx] 加载 encoder...');
      _encoderSession = OrtSession.fromFile(File(encoderPath), sessionOptions);
      debugPrint('[NllbOnnx] encoder 加载完成');
      debugPrint('[NllbOnnx]   inputs: ${_encoderSession!.inputNames}');
      debugPrint('[NllbOnnx]   outputs: ${_encoderSession!.outputNames}');

      debugPrint('[NllbOnnx] 加载 decoder...');
      _decoderSession = OrtSession.fromFile(File(decoderPath), sessionOptions);
      debugPrint('[NllbOnnx] decoder 加载完成');
      debugPrint('[NllbOnnx]   inputs: ${_decoderSession!.inputNames}');
      debugPrint('[NllbOnnx]   outputs: ${_decoderSession!.outputNames}');

      sessionOptions.release();

      _isReady = true;
      debugPrint('[NllbOnnx] ✅ 翻译引擎已就绪 (vocab=${_vocab!.length}, merges=${_merges!.length}, langs=${_langTokenIds!.length})');
    } catch (e, st) {
      debugPrint('[NllbOnnx] 初始化失败: $e');
      debugPrint('[NllbOnnx] $st');
      _isReady = false;
    }
  }

  /// 加载 HuggingFace tokenizer.json
  Future<void> _loadTokenizer(String tokenizerPath) async {
    try {
      final jsonStr = await File(tokenizerPath).readAsString();
      final json = jsonDecode(jsonStr) as Map<String, dynamic>;

      // 1. 解析 vocab from model.vocab
      final model = json['model'] as Map<String, dynamic>;
      final vocabMap = model['vocab'] as Map<String, dynamic>;
      _vocab = {};
      _vocabReverse = {};
      _langTokenIds = {};

      vocabMap.forEach((token, id) {
        final intId = (id as num).toInt();
        _vocab![token] = intId;
        _vocabReverse![intId] = token;

        // 提取语言 token (如 eng_Latn, zho_Hans 等)
        if (RegExp(r'^[a-z]{3}_[A-Z][a-z]{3}$').hasMatch(token)) {
          _langTokenIds![token] = intId;
        }
      });

      // 2. 解析 added_tokens 以获取特殊 token ID
      final addedTokens = json['added_tokens'] as List<dynamic>?;
      if (addedTokens != null) {
        for (final at in addedTokens) {
          final content = at['content'] as String;
          final id = (at['id'] as num).toInt();
          _vocab![content] = id;
          _vocabReverse![id] = content;

          if (content == '<pad>') _padId = id;
          if (content == '</s>') _eosId = id;
          if (content == '<unk>') _unkId = id;

          // 语言 token 也可能在 added_tokens 中
          if (RegExp(r'^[a-z]{3}_[A-Z][a-z]{3}$').hasMatch(content)) {
            _langTokenIds![content] = id;
          }
        }
      }

      // 3. 解析 BPE merge 规则
      final mergesList = model['merges'] as List<dynamic>;
      _merges = {};
      for (int i = 0; i < mergesList.length; i++) {
        _merges![mergesList[i] as String] = i;
      }

      debugPrint('[NllbOnnx] tokenizer 加载完成: ${_vocab!.length} tokens, ${_merges!.length} merges, ${_langTokenIds!.length} 语言');
      debugPrint('[NllbOnnx] 特殊 tokens: pad=$_padId, eos=$_eosId, unk=$_unkId');
    } catch (e) {
      debugPrint('[NllbOnnx] tokenizer 加载失败: $e');
    }
  }

  /// BPE 分词
  /// 实现标准 BPE: 先把文本 split 为 characters, 然后反复合并最高优先级的 pair
  List<int> _tokenize(String text) {
    if (_vocab == null || _merges == null) return [];

    final tokens = <int>[];
    // 按空格分词, 每个词加 ▁ 前缀 (SentencePiece convention)
    final words = text.split(RegExp(r'\s+'));

    for (final word in words) {
      if (word.isEmpty) continue;

      // SentencePiece: 添加 ▁ 前缀
      final prefixed = '▁$word';

      // 检查完整匹配
      if (_vocab!.containsKey(prefixed)) {
        tokens.add(_vocab![prefixed]!);
        continue;
      }

      // BPE: 先拆成单字符列表
      var parts = prefixed.split('').toList();

      // 反复执行 BPE merges
      while (parts.length > 1) {
        // 找到优先级最高 (index 最小) 的可合并 pair
        int bestIdx = -1;
        int bestRank = -1;
        for (int i = 0; i < parts.length - 1; i++) {
          final pair = '${parts[i]} ${parts[i + 1]}';
          final rank = _merges![pair];
          if (rank != null && (bestRank == -1 || rank < bestRank)) {
            bestRank = rank;
            bestIdx = i;
          }
        }
        if (bestIdx == -1) break; // 没有可合并的 pair 了

        // 执行合并
        final merged = parts[bestIdx] + parts[bestIdx + 1];
        parts = [
          ...parts.sublist(0, bestIdx),
          merged,
          ...parts.sublist(bestIdx + 2),
        ];
      }

      // 将子词转为 token id
      for (final part in parts) {
        final id = _vocab![part];
        if (id != null) {
          tokens.add(id);
        } else {
          tokens.add(_unkId);
        }
      }
    }

    return tokens;
  }

  /// 将 token IDs 转回文本
  String _detokenize(List<int> tokenIds) {
    if (_vocabReverse == null) return '';

    final buffer = StringBuffer();
    for (final id in tokenIds) {
      if (id == _eosId || id == _padId) continue;
      final token = _vocabReverse![id];
      if (token == null) continue;
      // 跳过语言标记
      if (_langTokenIds?.containsKey(token) ?? false) continue;
      buffer.write(token);
    }

    // SentencePiece: ▁ 替换为空格
    return buffer.toString().replaceAll('▁', ' ').trim();
  }

  /// 翻译
  Future<String> translate(
    String text,
    String srcLang,
    String tgtLang,
  ) async {
    if (!_isReady) {
      throw StateError('翻译引擎未初始化');
    }

    final stopwatch = Stopwatch()..start();

    try {
      // 1. Tokenize
      final tokenIds = _tokenize(text);
      if (tokenIds.isEmpty) return text;

      // 获取语言 token ID
      final srcLangId = _langTokenIds?[srcLang];
      final tgtLangId = _langTokenIds?[tgtLang];
      if (srcLangId == null || tgtLangId == null) {
        debugPrint('[NllbOnnx] 未知语言: src=$srcLang($srcLangId), tgt=$tgtLang($tgtLangId)');
        debugPrint('[NllbOnnx] 可用语言: ${_langTokenIds?.keys.take(10).toList()}...');
        return '[$tgtLang] $text';
      }

      // 2. 构建 encoder 输入: [src_lang_id, ...tokens, eos_id]
      final inputIds = [srcLangId, ...tokenIds, _eosId];
      final seqLen = inputIds.length;
      final attentionMask = List<int>.filled(seqLen, 1);

      debugPrint('[NllbOnnx] encoder input: $seqLen tokens');

      // 3. Run encoder
      final encoderInputIds = OrtValueTensor.createTensorWithDataList(
        Int64List.fromList(inputIds),
        [1, seqLen],
      );
      final encoderAttentionMask = OrtValueTensor.createTensorWithDataList(
        Int64List.fromList(attentionMask),
        [1, seqLen],
      );

      final encoderInputs = {
        'input_ids': encoderInputIds,
        'attention_mask': encoderAttentionMask,
      };

      final runOptions = OrtRunOptions();
      final encoderOutputs = _encoderSession!.run(
        runOptions,
        encoderInputs,
        _encoderSession!.outputNames,
      );

      final encoderHiddenStates = encoderOutputs[0]!;

      debugPrint('[NllbOnnx] encoder 完成: ${stopwatch.elapsedMilliseconds}ms');

      // 4. Autoregressive decoding (不使用 KV cache, 简单模式)
      var decoderInputIds = <int>[_eosId, tgtLangId];
      final maxLen = (seqLen * 3).clamp(10, 200);
      final outputTokens = <int>[];

      for (int step = 0; step < maxLen; step++) {
        final Map<String, OrtValue> decoderInputs = {};

        // decoder input_ids (完整序列)
        final decIds = OrtValueTensor.createTensorWithDataList(
          Int64List.fromList(decoderInputIds),
          [1, decoderInputIds.length],
        );
        decoderInputs['input_ids'] = decIds;

        // encoder_attention_mask
        decoderInputs['encoder_attention_mask'] = encoderAttentionMask;

        // encoder_hidden_states
        decoderInputs['encoder_hidden_states'] = encoderHiddenStates;

        // use_cache_branch = false (不使用 KV cache)
        final decoderInputNameSet = _decoderSession!.inputNames.toSet();
        if (decoderInputNameSet.contains('use_cache_branch')) {
          decoderInputs['use_cache_branch'] = OrtValueTensor.createTensorWithDataList(
            [false],
            [1],
          );
        }

        // 提供空的 past_key_values (merged model 需要)
        for (final inputName in _decoderSession!.inputNames) {
          if (inputName.startsWith('past_key_values') && !decoderInputs.containsKey(inputName)) {
            // 空的 past_key_values: shape [1, num_heads, 0, head_dim]
            // 对于 NLLB-200-distilled-600M: 12 layers, 16 heads, head_dim=64
            // decoder: past_key_values.N.decoder.key, .value, .encoder.key, .value
            decoderInputs[inputName] = OrtValueTensor.createTensorWithDataList(
              Float32List(0),
              [1, 16, 0, 64],
            );
          }
        }

        final decoderOutputs = _decoderSession!.run(
          runOptions,
          decoderInputs,
          ['logits'],
        );

        // 5. Get next token (greedy: argmax of last position)
        final logitsValue = decoderOutputs[0]!;
        final logitsData = logitsValue.value as List<List<List<double>>>;
        final lastLogits = logitsData[0].last; // [vocab_size]

        // Argmax
        int nextTokenId = 0;
        double maxVal = lastLogits[0];
        for (int i = 1; i < lastLogits.length; i++) {
          if (lastLogits[i] > maxVal) {
            maxVal = lastLogits[i];
            nextTokenId = i;
          }
        }

        // Release step outputs
        for (final o in decoderOutputs) {
          o?.release();
        }
        decIds.release();
        // 释放 use_cache_branch 和 past_key_values
        decoderInputs.forEach((key, value) {
          if (key != 'input_ids' && key != 'encoder_attention_mask' && key != 'encoder_hidden_states') {
            value.release();
          }
        });

        // EOS check
        if (nextTokenId == _eosId) break;

        outputTokens.add(nextTokenId);
        decoderInputIds = [...decoderInputIds, nextTokenId];
      }

      // 6. Cleanup
      encoderInputIds.release();
      encoderAttentionMask.release();
      encoderHiddenStates.release();
      runOptions.release();

      // 7. Detokenize
      final result = _detokenize(outputTokens);
      stopwatch.stop();
      debugPrint('[NllbOnnx] 翻译完成 (${stopwatch.elapsedMilliseconds}ms, ${outputTokens.length} tokens): "$text" -> "$result"');
      return result.isEmpty ? text : result;

    } catch (e, st) {
      debugPrint('[NllbOnnx] 翻译错误: $e');
      debugPrint('[NllbOnnx] $st');
      return '[$tgtLang] $text';
    }
  }

  /// 释放资源
  void dispose() {
    _encoderSession?.release();
    _decoderSession?.release();
    _encoderSession = null;
    _decoderSession = null;
    _isReady = false;
    try {
      OrtEnv.instance.release();
    } catch (_) {}
  }
}
