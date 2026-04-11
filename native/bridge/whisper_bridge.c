#include "whisper_bridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef AI_HAS_WHISPER
#include "whisper.h"
#endif

struct ai_whisper_context {
#ifdef AI_HAS_WHISPER
    struct whisper_context* wctx;
#else
    void* wctx;
#endif
    char result_text[4096];
    char result_lang[16];
};

ai_whisper_context* ai_whisper_init(const char* model_path) {
    if (!model_path) return NULL;
    ai_whisper_context* ctx = (ai_whisper_context*)calloc(1, sizeof(ai_whisper_context));
    if (!ctx) return NULL;
#ifdef AI_HAS_WHISPER
    struct whisper_context_params cparams = whisper_context_default_params();
    ctx->wctx = whisper_init_from_file_with_params(model_path, cparams);
    if (!ctx->wctx) { free(ctx); return NULL; }
#else
    fprintf(stderr, "[ai_whisper] stub mode\n");
    ctx->wctx = NULL;
#endif
    fprintf(stderr, "[ai_whisper] loaded: %s\n", model_path);
    return ctx;
}

ai_whisper_result ai_whisper_transcribe(ai_whisper_context* ctx, const char* audio_path) {
    ai_whisper_result result = { "", "und" };
    if (!ctx || !audio_path) return result;
#ifdef AI_HAS_WHISPER
    /* real impl */
#else
    strncpy(ctx->result_text, "[stub] transcription not available", sizeof(ctx->result_text) - 1);
    strncpy(ctx->result_lang, "und", sizeof(ctx->result_lang) - 1);
    result.text = ctx->result_text;
    result.lang = ctx->result_lang;
#endif
    return result;
}

void ai_whisper_free(ai_whisper_context* ctx) {
    if (!ctx) return;
#ifdef AI_HAS_WHISPER
    if (ctx->wctx) whisper_free(ctx->wctx);
#endif
    free(ctx);
}
