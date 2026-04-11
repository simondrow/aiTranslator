#include "fasttext_bridge.h"

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>
#include <utility>

#ifdef AI_HAS_FASTTEXT
#include "fasttext.h"
#endif

struct ai_fasttext_context {
#ifdef AI_HAS_FASTTEXT
    fasttext::FastText model;
#endif
    char result_label[64];
    bool loaded;
};

extern "C" {

ai_fasttext_context* ai_fasttext_init(const char* model_path) {
    if (!model_path) return nullptr;

    ai_fasttext_context* ctx = new (std::nothrow) ai_fasttext_context();
    if (!ctx) return nullptr;

    ctx->loaded = false;
    memset(ctx->result_label, 0, sizeof(ctx->result_label));

#ifdef AI_HAS_FASTTEXT
    try {
        ctx->model.loadModel(std::string(model_path));
        ctx->loaded = true;
        fprintf(stderr, "[ai_fasttext] model loaded: %s\n", model_path);
    } catch (const std::exception& e) {
        fprintf(stderr, "[ai_fasttext] load failed: %s\n", e.what());
        delete ctx;
        return nullptr;
    }
#else
    fprintf(stderr, "[ai_fasttext] stub mode (AI_HAS_FASTTEXT not defined)\n");
    ctx->loaded = true;
#endif

    return ctx;
}

ai_fasttext_result ai_fasttext_predict(ai_fasttext_context* ctx, const char* text) {
    ai_fasttext_result result;
    result.lang = "__label__und";
    result.confidence = 0.0f;

    if (!ctx || !text || strlen(text) == 0) return result;

#ifdef AI_HAS_FASTTEXT
    try {
        std::istringstream iss(std::string(text) + "\n");
        std::vector<std::pair<fasttext::real, std::string>> predictions;

        ctx->model.predictLine(iss, predictions, 1, 0.0f);

        if (!predictions.empty()) {
            // predictions[0].second is like "__label__zh"
            strncpy(ctx->result_label, predictions[0].second.c_str(),
                    sizeof(ctx->result_label) - 1);
            ctx->result_label[sizeof(ctx->result_label) - 1] = '\0';
            result.lang = ctx->result_label;
            result.confidence = static_cast<float>(predictions[0].first);
        }
    } catch (const std::exception& e) {
        fprintf(stderr, "[ai_fasttext] predict error: %s\n", e.what());
    }
#else
    // Stub: simple heuristic based on first byte
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
    ctx->result_label[sizeof(ctx->result_label) - 1] = '\0';
    result.lang = ctx->result_label;
#endif

    return result;
}

void ai_fasttext_free(ai_fasttext_context* ctx) {
    if (ctx) {
        delete ctx;
    }
}

} // extern "C"
