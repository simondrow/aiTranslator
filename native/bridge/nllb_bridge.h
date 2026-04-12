#ifndef AI_NLLB_BRIDGE_H
#define AI_NLLB_BRIDGE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct ai_nllb_context ai_nllb_context;

/// Initialize NLLB translation context
/// @param model_dir Path to CTranslate2 model directory (containing model.bin, etc.)
/// @param sp_model_path Path to sentencepiece.bpe.model
/// @return Opaque context pointer, or NULL on failure
ai_nllb_context* ai_nllb_init(const char* model_dir, const char* sp_model_path);

/// Translate text
/// @param ctx Context from ai_nllb_init
/// @param text Input text (UTF-8)
/// @param src_lang Source NLLB language code (e.g., "zho_Hans")
/// @param tgt_lang Target NLLB language code (e.g., "eng_Latn")
/// @return Translated text (caller must free via ai_nllb_free_string), or NULL on error
char* ai_nllb_translate(ai_nllb_context* ctx, const char* text,
                        const char* src_lang, const char* tgt_lang);

/// Free a string returned by ai_nllb_translate
void ai_nllb_free_string(char* str);

/// Free the NLLB context
void ai_nllb_free(ai_nllb_context* ctx);

/// Check if context is properly initialized with real engine
int ai_nllb_is_ready(ai_nllb_context* ctx);

#ifdef __cplusplus
}
#endif

#endif
