/// 消息输入类型
enum InputType {
  voice,
  text,
}

/// 对话消息模型
class Message {
  final String id;
  final String originalText;
  final String translatedText;
  final String sourceLanguage;
  final String targetLanguage;
  final bool isFromMe;
  final DateTime timestamp;
  final InputType inputType;

  const Message({
    required this.id,
    required this.originalText,
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.isFromMe,
    required this.timestamp,
    required this.inputType,
  });

  Message copyWith({
    String? id,
    String? originalText,
    String? translatedText,
    String? sourceLanguage,
    String? targetLanguage,
    bool? isFromMe,
    DateTime? timestamp,
    InputType? inputType,
  }) {
    return Message(
      id: id ?? this.id,
      originalText: originalText ?? this.originalText,
      translatedText: translatedText ?? this.translatedText,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      isFromMe: isFromMe ?? this.isFromMe,
      timestamp: timestamp ?? this.timestamp,
      inputType: inputType ?? this.inputType,
    );
  }
}
