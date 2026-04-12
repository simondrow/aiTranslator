#include "nllb_bridge.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include <sstream>

#ifdef AI_HAS_CTRANSLATE2
#include <ctranslate2/translator.h>
#include <sentencepiece_processor.h>
#endif

struct ai_nllb_context {
#ifdef AI_HAS_CTRANSLATE2
    ctranslate2::Translator* translator;
    sentencepiece::SentencePieceProcessor* sp;
#endif
    char model_dir[1024];
    bool loaded;
};

extern "C" {

ai_nllb_context* ai_nllb_init(const char* model_dir, const char* sp_model_path) {
    if (!model_dir) return nullptr;

    auto* ctx = new (std::nothrow) ai_nllb_context();
    if (!ctx) return nullptr;
    memset(ctx->model_dir, 0, sizeof(ctx->model_dir));
    strncpy(ctx->model_dir, model_dir, sizeof(ctx->model_dir) - 1);
    ctx->loaded = false;

#ifdef AI_HAS_CTRANSLATE2
    try {
        // Load CTranslate2 model
        ctx->translator = new ctranslate2::Translator(
            std::string(model_dir),
            ctranslate2::Device::CPU,
            /* device_index= */ 0,
            ctranslate2::ComputeType::INT8
        );

        // Load SentencePiece tokenizer
        ctx->sp = new sentencepiece::SentencePieceProcessor();
        auto status = ctx->sp->Load(std::string(sp_model_path));
        if (!status.ok()) {
            fprintf(stderr, "[ai_nllb] SentencePiece load failed: %s\n",
                    status.ToString().c_str());
            delete ctx->translator;
            delete ctx->sp;
            delete ctx;
            return nullptr;
        }

        ctx->loaded = true;
        fprintf(stderr, "[ai_nllb] CTranslate2 + SentencePiece loaded OK\n");
        fprintf(stderr, "[ai_nllb]   model: %s\n", model_dir);
        fprintf(stderr, "[ai_nllb]   sp:    %s\n", sp_model_path);
    } catch (const std::exception& e) {
        fprintf(stderr, "[ai_nllb] init failed: %s\n", e.what());
        delete ctx;
        return nullptr;
    }
#else
    // Stub mode — no real engine
    fprintf(stderr, "[ai_nllb] stub mode (AI_HAS_CTRANSLATE2 not defined)\n");
    fprintf(stderr, "[ai_nllb] model_dir: %s\n", model_dir);
    ctx->loaded = false;
#endif

    return ctx;
}

char* ai_nllb_translate(ai_nllb_context* ctx, const char* text,
                        const char* src_lang, const char* tgt_lang) {
    if (!ctx || !text || !src_lang || !tgt_lang) return nullptr;

#ifdef AI_HAS_CTRANSLATE2
    if (!ctx->loaded) goto stub;

    try {
        // 1. Tokenize input with SentencePiece
        std::vector<std::string> tokens;
        ctx->sp->Encode(std::string(text), &tokens);

        // 2. Prepend source language token, append </s>
        // NLLB format: src_lang_token <tokens...> </s>
        tokens.insert(tokens.begin(), std::string(src_lang));
        tokens.push_back("</s>");

        // 3. Create target prefix with target language token
        std::vector<std::string> target_prefix = { std::string(tgt_lang) };

        // 4. Translate
        std::vector<std::vector<std::string>> batch = { tokens };
        std::vector<std::vector<std::string>> target_prefix_batch = { target_prefix };

        ctranslate2::TranslationOptions options;
        options.beam_size = 4;
        options.max_decoding_length = 256;

        auto results = ctx->translator->translate_batch(
            batch, target_prefix_batch, options);

        if (results.empty() || results[0].hypotheses.empty()) {
            goto stub;
        }

        // 5. Get output tokens (skip the target language prefix token)
        const auto& output_tokens = results[0].output();
        std::vector<int> token_ids;

        // Convert tokens back to ids for SentencePiece decoding
        // Skip first token (target language token) and last </s>
        std::vector<std::string> clean_tokens;
        for (size_t i = 1; i < output_tokens.size(); ++i) {
            if (output_tokens[i] == "</s>") break;
            clean_tokens.push_back(output_tokens[i]);
        }

        // 6. Detokenize with SentencePiece
        std::string decoded;
        ctx->sp->Decode(clean_tokens, &decoded);

        // 7. Return as C string (caller must free)
        char* result = (char*)malloc(decoded.size() + 1);
        if (result) {
            memcpy(result, decoded.c_str(), decoded.size() + 1);
        }
        return result;

    } catch (const std::exception& e) {
        fprintf(stderr, "[ai_nllb] translate error: %s\n", e.what());
        goto stub;
    }

stub:
#endif
    {
        // Stub fallback: return "[src->tgt] text"
        size_t len = strlen(text) + strlen(src_lang) + strlen(tgt_lang) + 64;
        char* result = (char*)malloc(len);
        if (result) {
            snprintf(result, len, "[%s->%s] %s", src_lang, tgt_lang, text);
        }
        return result;
    }
}

void ai_nllb_free_string(char* str) {
    if (str) free(str);
}

void ai_nllb_free(ai_nllb_context* ctx) {
    if (!ctx) return;
#ifdef AI_HAS_CTRANSLATE2
    if (ctx->loaded) {
        delete ctx->translator;
        delete ctx->sp;
    }
#endif
    delete ctx;
}

int ai_nllb_is_ready(ai_nllb_context* ctx) {
    if (!ctx) return 0;
    return ctx->loaded ? 1 : 0;
}

} // extern "C"
