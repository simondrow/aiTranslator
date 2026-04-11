#ifndef AI_NLLB_BRIDGE_H
#define AI_NLLB_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ai_nllb_context ai_nllb_context;

ai_nllb_context* ai_nllb_init(const char* model_path);
char* ai_nllb_translate(ai_nllb_context* ctx, const char* text, const char* src_lang, const char* tgt_lang);
void ai_nllb_free_string(char* str);
void ai_nllb_free(ai_nllb_context* ctx);

#ifdef __cplusplus
}
#endif

#endif
