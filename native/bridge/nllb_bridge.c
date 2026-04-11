#include "nllb_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct ai_nllb_context {
    void* translator;
    void* tokenizer;
    char model_path[1024];
};

ai_nllb_context* ai_nllb_init(const char* model_path) {
    if (!model_path) return NULL;
    ai_nllb_context* ctx = (ai_nllb_context*)calloc(1, sizeof(ai_nllb_context));
    if (!ctx) return NULL;
    strncpy(ctx->model_path, model_path, sizeof(ctx->model_path) - 1);
#ifdef AI_HAS_CTRANSLATE2
    /* real impl */
#else
    fprintf(stderr, "[ai_nllb] stub mode\n");
    ctx->translator = NULL;
    ctx->tokenizer = NULL;
#endif
    fprintf(stderr, "[ai_nllb] loaded: %s\n", model_path);
    return ctx;
}

char* ai_nllb_translate(ai_nllb_context* ctx, const char* text, const char* src_lang, const char* tgt_lang) {
    if (!ctx || !text || !src_lang || !tgt_lang) return NULL;
    size_t len = strlen(text) + strlen(src_lang) + strlen(tgt_lang) + 64;
    char* result = (char*)malloc(len);
    if (result) snprintf(result, len, "[%s->%s] %s", src_lang, tgt_lang, text);
    return result;
}

void ai_nllb_free_string(char* str) { if (str) free(str); }
void ai_nllb_free(ai_nllb_context* ctx) { if (ctx) free(ctx); }
