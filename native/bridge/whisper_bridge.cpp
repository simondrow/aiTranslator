#include "whisper_bridge.h"

#include <TargetConditionals.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#ifndef WHISPER_VERSION
#define WHISPER_VERSION "1.8.4"
#endif

#ifdef AI_HAS_WHISPER
#include "whisper.h"
#endif

// ============================================================
// WAV file reader — reads 16-bit PCM WAV and converts to float32
// Assumes: mono, 16kHz, 16-bit (the format our AudioService produces)
// ============================================================

#ifndef WHISPER_VERSION
#define WHISPER_VERSION "1.8.4"
#endif

#ifdef AI_HAS_WHISPER

struct wav_header {
    char     riff[4];        // "RIFF"
    uint32_t file_size;
    char     wave[4];        // "WAVE"
};

static bool read_wav_to_float32(const char* path, float** out_data, int* out_samples) {
    FILE* f = fopen(path, "rb");
    if (!f) {
        fprintf(stderr, "[ai_whisper] cannot open audio file: %s\n", path);
        return false;
    }

    // Read RIFF header
    struct wav_header hdr;
    if (fread(&hdr, sizeof(hdr), 1, f) != 1) {
        fprintf(stderr, "[ai_whisper] failed to read WAV header\n");
        fclose(f);
        return false;
    }

    if (memcmp(hdr.riff, "RIFF", 4) != 0 || memcmp(hdr.wave, "WAVE", 4) != 0) {
        fprintf(stderr, "[ai_whisper] not a valid WAV file\n");
        fclose(f);
        return false;
    }

    // Parse chunks to find "data" chunk
    uint16_t audio_format   = 0;
    uint16_t num_channels   = 0;
    uint32_t sample_rate    = 0;
    uint16_t bits_per_sample = 0;
    uint32_t data_size      = 0;
    bool     found_fmt      = false;
    bool     found_data     = false;

    while (!found_data) {
        char     chunk_id[4];
        uint32_t chunk_size;

        if (fread(chunk_id, 4, 1, f) != 1) break;
        if (fread(&chunk_size, 4, 1, f) != 1) break;

        if (memcmp(chunk_id, "fmt ", 4) == 0) {
            long pos = ftell(f);
            if (chunk_size >= 16) {
                fread(&audio_format,    2, 1, f);
                fread(&num_channels,    2, 1, f);
                fread(&sample_rate,     4, 1, f);
                uint32_t byte_rate;
                fread(&byte_rate,       4, 1, f);
                uint16_t block_align;
                fread(&block_align,     2, 1, f);
                fread(&bits_per_sample, 2, 1, f);
            }
            fseek(f, pos + chunk_size, SEEK_SET);
            found_fmt = true;
        } else if (memcmp(chunk_id, "data", 4) == 0) {
            data_size = chunk_size;
            found_data = true;
        } else {
            // Skip unknown chunk
            fseek(f, chunk_size, SEEK_CUR);
        }
    }

    if (!found_fmt || !found_data) {
        fprintf(stderr, "[ai_whisper] WAV missing fmt or data chunk\n");
        fclose(f);
        return false;
    }

    if (audio_format != 1) {
        fprintf(stderr, "[ai_whisper] unsupported WAV format %d (need PCM=1)\n", audio_format);
        fclose(f);
        return false;
    }

    fprintf(stderr, "[ai_whisper] WAV: %d Hz, %d ch, %d bit, %u bytes\n",
            sample_rate, num_channels, bits_per_sample, data_size);

    // Read raw PCM data
    int num_samples_per_channel;
    float* pcm = NULL;

    if (bits_per_sample == 16) {
        int total_samples = data_size / 2;  // 2 bytes per sample
        num_samples_per_channel = total_samples / num_channels;

        int16_t* raw = (int16_t*)malloc(data_size);
        if (!raw) { fclose(f); return false; }

        size_t read = fread(raw, 1, data_size, f);
        if (read < data_size) {
            fprintf(stderr, "[ai_whisper] WAV short read: %zu / %u\n", read, data_size);
        }

        // Convert to float32 mono
        pcm = (float*)malloc(num_samples_per_channel * sizeof(float));
        if (!pcm) { free(raw); fclose(f); return false; }

        if (num_channels == 1) {
            for (int i = 0; i < num_samples_per_channel; i++) {
                pcm[i] = (float)raw[i] / 32768.0f;
            }
        } else {
            // Mix to mono
            for (int i = 0; i < num_samples_per_channel; i++) {
                float sum = 0.0f;
                for (int c = 0; c < num_channels; c++) {
                    sum += (float)raw[i * num_channels + c] / 32768.0f;
                }
                pcm[i] = sum / (float)num_channels;
            }
        }
        free(raw);
    } else if (bits_per_sample == 32 && audio_format == 3) {
        // IEEE float32
        int total_samples = data_size / 4;
        num_samples_per_channel = total_samples / num_channels;

        float* raw = (float*)malloc(data_size);
        if (!raw) { fclose(f); return false; }
        fread(raw, 1, data_size, f);

        pcm = (float*)malloc(num_samples_per_channel * sizeof(float));
        if (!pcm) { free(raw); fclose(f); return false; }

        if (num_channels == 1) {
            memcpy(pcm, raw, num_samples_per_channel * sizeof(float));
        } else {
            for (int i = 0; i < num_samples_per_channel; i++) {
                float sum = 0.0f;
                for (int c = 0; c < num_channels; c++) {
                    sum += raw[i * num_channels + c];
                }
                pcm[i] = sum / (float)num_channels;
            }
        }
        free(raw);
    } else {
        fprintf(stderr, "[ai_whisper] unsupported bits_per_sample: %d\n", bits_per_sample);
        fclose(f);
        return false;
    }

    fclose(f);

    // Resample to 16kHz if needed
    if (sample_rate != 16000) {
        int new_len = (int)((float)num_samples_per_channel * 16000.0f / (float)sample_rate);
        float* resampled = (float*)malloc(new_len * sizeof(float));
        if (!resampled) { free(pcm); return false; }

        for (int i = 0; i < new_len; i++) {
            float src_idx = (float)i * (float)sample_rate / 16000.0f;
            int idx = (int)src_idx;
            float frac = src_idx - (float)idx;
            if (idx + 1 < num_samples_per_channel) {
                resampled[i] = pcm[idx] * (1.0f - frac) + pcm[idx + 1] * frac;
            } else if (idx < num_samples_per_channel) {
                resampled[i] = pcm[idx];
            } else {
                resampled[i] = 0.0f;
            }
        }
        free(pcm);
        pcm = resampled;
        num_samples_per_channel = new_len;

        fprintf(stderr, "[ai_whisper] resampled %d Hz -> 16000 Hz (%d samples)\n",
                sample_rate, new_len);
    }

    *out_data = pcm;
    *out_samples = num_samples_per_channel;
    return true;
}

#endif // AI_HAS_WHISPER

// ============================================================
// Bridge implementation
// ============================================================

struct ai_whisper_context {
#ifndef WHISPER_VERSION
#define WHISPER_VERSION "1.8.4"
#endif

#ifdef AI_HAS_WHISPER
    struct whisper_context* wctx;
#else
    void* wctx;
#endif
    char result_text[8192];
    char result_lang[16];
};

ai_whisper_context* ai_whisper_init(const char* model_path) {
    if (!model_path) return NULL;

    ai_whisper_context* ctx = (ai_whisper_context*)calloc(1, sizeof(ai_whisper_context));
    if (!ctx) return NULL;

#ifndef WHISPER_VERSION
#define WHISPER_VERSION "1.8.4"
#endif

#ifdef AI_HAS_WHISPER
    struct whisper_context_params cparams = whisper_context_default_params();
    // Use GPU on real device, disable on Simulator (MTLSimDriver crashes on XPC shmem)
#if TARGET_OS_SIMULATOR
    cparams.use_gpu = false;
    fprintf(stderr, "[ai_whisper] Simulator detected - Metal GPU disabled\n");
#else
    cparams.use_gpu = true;
#endif

    fprintf(stderr, "[ai_whisper] loading model: %s\n", model_path);
    ctx->wctx = whisper_init_from_file_with_params(model_path, cparams);
    if (!ctx->wctx) {
        fprintf(stderr, "[ai_whisper] failed to load model\n");
        free(ctx);
        return NULL;
    }
    fprintf(stderr, "[ai_whisper] model loaded successfully (version: %s)\n",
            whisper_version());
#else
    fprintf(stderr, "[ai_whisper] stub mode — whisper.cpp not linked\n");
    ctx->wctx = NULL;
#endif

    return ctx;
}

ai_whisper_result ai_whisper_transcribe(ai_whisper_context* ctx, const char* audio_path) {
    ai_whisper_result result = { "", "und" };
    if (!ctx || !audio_path) return result;

#ifndef WHISPER_VERSION
#define WHISPER_VERSION "1.8.4"
#endif

#ifdef AI_HAS_WHISPER
    if (!ctx->wctx) {
        strncpy(ctx->result_text, "", sizeof(ctx->result_text) - 1);
        strncpy(ctx->result_lang, "und", sizeof(ctx->result_lang) - 1);
        result.text = ctx->result_text;
        result.lang = ctx->result_lang;
        return result;
    }

    // Read WAV to float32 PCM
    float* pcm_data = NULL;
    int    pcm_samples = 0;

    if (!read_wav_to_float32(audio_path, &pcm_data, &pcm_samples)) {
        fprintf(stderr, "[ai_whisper] failed to read audio: %s\n", audio_path);
        strncpy(ctx->result_text, "", sizeof(ctx->result_text) - 1);
        strncpy(ctx->result_lang, "und", sizeof(ctx->result_lang) - 1);
        result.text = ctx->result_text;
        result.lang = ctx->result_lang;
        return result;
    }

    fprintf(stderr, "[ai_whisper] transcribing %d samples (%.1f sec)\n",
            pcm_samples, (float)pcm_samples / 16000.0f);

    // Configure whisper params
    struct whisper_full_params wparams = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    wparams.print_realtime   = false;
    wparams.print_progress   = false;
    wparams.print_timestamps = false;
    wparams.print_special    = false;
    wparams.single_segment   = false;
    wparams.no_timestamps    = true;
    wparams.language         = "auto";  // Auto-detect language
    wparams.n_threads        = 4;

    // Run inference
    int ret = whisper_full(ctx->wctx, wparams, pcm_data, pcm_samples);
    free(pcm_data);

    if (ret != 0) {
        fprintf(stderr, "[ai_whisper] whisper_full failed: %d\n", ret);
        strncpy(ctx->result_text, "", sizeof(ctx->result_text) - 1);
        strncpy(ctx->result_lang, "und", sizeof(ctx->result_lang) - 1);
        result.text = ctx->result_text;
        result.lang = ctx->result_lang;
        return result;
    }

    // Get detected language
    int lang_id = whisper_full_lang_id(ctx->wctx);
    const char* lang_str = whisper_lang_str(lang_id);
    strncpy(ctx->result_lang, lang_str ? lang_str : "und", sizeof(ctx->result_lang) - 1);

    // Concatenate all segment texts
    ctx->result_text[0] = '\0';
    int n_segments = whisper_full_n_segments(ctx->wctx);
    size_t offset = 0;

    for (int i = 0; i < n_segments; i++) {
        const char* seg_text = whisper_full_get_segment_text(ctx->wctx, i);
        if (seg_text) {
            size_t seg_len = strlen(seg_text);
            if (offset + seg_len < sizeof(ctx->result_text) - 1) {
                memcpy(ctx->result_text + offset, seg_text, seg_len);
                offset += seg_len;
            }
        }
    }
    ctx->result_text[offset] = '\0';

    // Trim leading whitespace
    char* trimmed = ctx->result_text;
    while (*trimmed == ' ' || *trimmed == '\n' || *trimmed == '\r' || *trimmed == '\t') {
        trimmed++;
    }
    if (trimmed != ctx->result_text) {
        memmove(ctx->result_text, trimmed, strlen(trimmed) + 1);
    }

    fprintf(stderr, "[ai_whisper] result lang=%s text=\"%.80s%s\"\n",
            ctx->result_lang, ctx->result_text,
            strlen(ctx->result_text) > 80 ? "..." : "");

    result.text = ctx->result_text;
    result.lang = ctx->result_lang;
    return result;

#else
    // Stub mode
    strncpy(ctx->result_text, "[stub] whisper.cpp not available", sizeof(ctx->result_text) - 1);
    strncpy(ctx->result_lang, "und", sizeof(ctx->result_lang) - 1);
    result.text = ctx->result_text;
    result.lang = ctx->result_lang;
    return result;
#endif
}

void ai_whisper_free(ai_whisper_context* ctx) {
    if (!ctx) return;
#ifndef WHISPER_VERSION
#define WHISPER_VERSION "1.8.4"
#endif

#ifdef AI_HAS_WHISPER
    if (ctx->wctx) whisper_free(ctx->wctx);
#endif
    free(ctx);
}
