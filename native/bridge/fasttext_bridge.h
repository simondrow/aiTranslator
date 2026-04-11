#ifndef AI_FASTTEXT_BRIDGE_H
#define AI_FASTTEXT_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ai_fasttext_context ai_fasttext_context;

typedef struct {
    const char* lang;
    float confidence;
} ai_fasttext_result;

ai_fasttext_context* ai_fasttext_init(const char* model_path);
ai_fasttext_result ai_fasttext_predict(ai_fasttext_context* ctx, const char* text);
void ai_fasttext_free(ai_fasttext_context* ctx);

#ifdef __cplusplus
}
#endif

#endif
