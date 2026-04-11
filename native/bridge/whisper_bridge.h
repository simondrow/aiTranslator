#ifndef AI_WHISPER_BRIDGE_H
#define AI_WHISPER_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ai_whisper_context ai_whisper_context;

typedef struct {
    const char* text;
    const char* lang;
} ai_whisper_result;

ai_whisper_context* ai_whisper_init(const char* model_path);
ai_whisper_result ai_whisper_transcribe(ai_whisper_context* ctx, const char* audio_path);
void ai_whisper_free(ai_whisper_context* ctx);

#ifdef __cplusplus
}
#endif

#endif
