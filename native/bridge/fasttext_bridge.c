#include "fasttext_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct ai_fasttext_context {
    void* model;
    char result_label[64];
};

ai_fasttext_context* ai_fasttext_init(const char* model_path) {
    if (!model_path) return NULL;
    ai_fasttext_context* ctx = (ai_fasttext_context*)calloc(1, sizeof(ai_fasttext_context));
    if (!ctx) return NULL;
#ifdef AI_HAS_FASTTEXT
    /* real impl */
#else
    fprintf(stderr, "[ai_fasttext] stub mode\n");
    ctx->model = NULL;
#endif
    fprintf(stderr, "[ai_fasttext] loaded: %s\n", model_path);
    return ctx;
}

ai_fasttext_result ai_fasttext_predict(ai_fasttext_context* ctx, const char* text) {
    ai_fasttext_result result = { "__label__und", 0.0f };
    if (!ctx || !text || strlen(text) == 0) return result;
#ifdef AI_HAS_FASTTEXT
    /* real impl */
#else
    unsigned char first = (unsigned char)text[0];
    if (first >= 0xE4 && first <= 0xE9) {
        strncpy(ctx->result_label, "__label__zh", sizeof(ctx->result_label) - 1);
        result.confidence = 0.85f;
    } else if (first < 0x80) {
        strncpy(ctx->result_label, "__label__en", sizeof(ctx->result_label) - 1);
        result.confidence = 0.80f;
    } else {
        strncpy(ctx->result_label, "__label__und", sizeof(ctx->result_label) - 1);
        result.confidence = 0.30f;
    }
    result.lang = ctx->result_label;
#endif
    return result;
}

void ai_fasttext_free(ai_fasttext_context* ctx) {
    if (ctx) free(ctx);
}
