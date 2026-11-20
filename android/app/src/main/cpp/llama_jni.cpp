#include <jni.h>
#include <string>
#include <vector>
#include <atomic>
#include <mutex>
#include <algorithm>
#include <android/log.h>
#include "llama.h"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "HTT_LLAMA", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "HTT_LLAMA", __VA_ARGS__)

static std::mutex g_mutex;
static llama_model * g_model = nullptr;
static llama_context * g_ctx = nullptr;
static llama_sampler * g_smpl = nullptr;
static int g_ctx_len = 1024;
static std::atomic<bool> g_cancel{false};
static bool g_backend_init = false;

static void free_all_locked() {
    if (g_smpl) {
        llama_sampler_free(g_smpl);
        g_smpl = nullptr;
    }
    if (g_ctx) {
        llama_free(g_ctx);
        g_ctx = nullptr;
    }
    if (g_model) {
        llama_model_free(g_model);
        g_model = nullptr;
    }
}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_tomy_httnavicompanion_audio_LlamaNativeBridge_nativeLoadModel(
        JNIEnv * env,
        jobject /* thiz */,
        jstring jpath,
        jint ctxLen,
        jint threads) {
    std::lock_guard<std::mutex> lock(g_mutex);
    const char * path = env->GetStringUTFChars(jpath, nullptr);
    if (!path) return JNI_FALSE;
    std::string model_path(path);
    env->ReleaseStringUTFChars(jpath, path);

    free_all_locked();

    if (!g_backend_init) {
        llama_backend_init();
        g_backend_init = true;
    }

    llama_model_params mparams = llama_model_default_params();
    mparams.n_gpu_layers = 0;
    mparams.use_mmap = true;
    mparams.use_mlock = false;

    g_model = llama_model_load_from_file(model_path.c_str(), mparams);
    if (!g_model) {
        LOGE("Failed to load GGUF model: %s", model_path.c_str());
        return JNI_FALSE;
    }

    llama_context_params cparams = llama_context_default_params();
    g_ctx_len = std::max(512, (int)ctxLen);
    cparams.n_ctx = (uint32_t)g_ctx_len;
    cparams.n_batch = 256;
    cparams.n_ubatch = 256;
    cparams.n_seq_max = 1;
    cparams.offload_kqv = false;
    cparams.no_perf = true;
    int thr = std::max(2, std::min(6, (int)threads));
    cparams.n_threads = thr;
    cparams.n_threads_batch = thr;

    g_ctx = llama_init_from_model(g_model, cparams);
    if (!g_ctx) {
        LOGE("Failed to init llama context");
        free_all_locked();
        return JNI_FALSE;
    }

    llama_sampler_chain_params sparams = llama_sampler_chain_default_params();
    g_smpl = llama_sampler_chain_init(sparams);
    llama_sampler_chain_add(g_smpl, llama_sampler_init_penalties(64, 1.12f, 0.0f, 0.0f));
    llama_sampler_chain_add(g_smpl, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(g_smpl, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add(g_smpl, llama_sampler_init_temp(0.75f));
    llama_sampler_chain_add(g_smpl, llama_sampler_init_dist(1337));

    LOGI("Loaded GGUF model OK (ctx=%d, threads=%d)", g_ctx_len, thr);
    return JNI_TRUE;
}

extern "C" JNIEXPORT void JNICALL
Java_com_tomy_httnavicompanion_audio_LlamaNativeBridge_nativeUnload(JNIEnv * /* env */, jobject /* thiz */) {
    g_cancel.store(true);
    std::lock_guard<std::mutex> lock(g_mutex);
    free_all_locked();
}

extern "C" JNIEXPORT void JNICALL
Java_com_tomy_httnavicompanion_audio_LlamaNativeBridge_nativeCancel(JNIEnv * /* env */, jobject /* thiz */) {
    g_cancel.store(true);
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_tomy_httnavicompanion_audio_LlamaNativeBridge_nativeGenerate(
        JNIEnv * env,
        jobject /* thiz */,
        jstring jprompt,
        jobject callback) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_model || !g_ctx || !g_smpl) {
        return env->NewStringUTF("");
    }
    g_cancel.store(false);

    const char * cprompt = env->GetStringUTFChars(jprompt, nullptr);
    if (!cprompt) return env->NewStringUTF("");
    std::string prompt(cprompt);
    env->ReleaseStringUTFChars(jprompt, cprompt);

    const llama_vocab * vocab = llama_model_get_vocab(g_model);
    int max_toks = (int)prompt.size() + 64;
    std::vector<llama_token> tokens(max_toks);
    int n_tokens = llama_tokenize(vocab, prompt.c_str(), (int32_t)prompt.size(), tokens.data(), max_toks, true, true);
    if (n_tokens <= 0) {
        return env->NewStringUTF("");
    }

    int max_prompt = std::max(128, g_ctx_len - 96);
    int total_prompt = std::min(n_tokens, max_prompt);

    llama_kv_self_clear(g_ctx);
    for (int off = 0; off < total_prompt; ) {
        int step = std::min(128, total_prompt - off);
        llama_batch batch = llama_batch_get_one(tokens.data() + off, step);
        if (llama_decode(g_ctx, batch) != 0) {
            return env->NewStringUTF("");
        }
        off += step;
    }

    jmethodID onTokenMethod = nullptr;
    if (callback) {
        jclass cls = env->GetObjectClass(callback);
        if (cls) {
            onTokenMethod = env->GetMethodID(cls, "onToken", "(Ljava/lang/String;)V");
            env->DeleteLocalRef(cls);
        }
    }

    std::string accumulated;
    std::string utf8_pending;
    int max_gen = std::min(160, std::max(32, g_ctx_len - total_prompt - 4));

    for (int i = 0; i < max_gen; ++i) {
        if (g_cancel.load()) break;
        llama_token new_tok = llama_sampler_sample(g_smpl, g_ctx, -1);
        if (llama_vocab_is_eog(vocab, new_tok)) break;

        char piece[64];
        int n = llama_token_to_piece(vocab, new_tok, piece, sizeof(piece), 0, true);
        if (n > 0) {
            utf8_pending.append(piece, n);
            // Check complete UTF-8 sequence before sending to JNI NewStringUTF
            size_t valid_len = utf8_pending.size();
            while (valid_len > 0) {
                unsigned char c = (unsigned char)utf8_pending[valid_len - 1];
                if ((c & 0x80) == 0) break;
                // Walk back to start of multi-byte char
                size_t start = valid_len - 1;
                while (start > 0 && (((unsigned char)utf8_pending[start] & 0xC0) == 0x80)) {
                    start--;
                }
                unsigned char lead = (unsigned char)utf8_pending[start];
                size_t expected = 1;
                if ((lead & 0xE0) == 0xC0) expected = 2;
                else if ((lead & 0xF0) == 0xE0) expected = 3;
                else if ((lead & 0xF8) == 0xF0) expected = 4;
                if (valid_len - start < expected) {
                    valid_len = start;
                }
                break;
            }
            if (valid_len > 0) {
                std::string chunk = utf8_pending.substr(0, valid_len);
                utf8_pending.erase(0, valid_len);
                if (chunk.find("<|im_end|>") != std::string::npos || chunk.find("<|endoftext|>") != std::string::npos) {
                    break;
                }
                accumulated += chunk;
                if (callback && onTokenMethod) {
                    jstring jchunk = env->NewStringUTF(accumulated.c_str());
                    if (jchunk) {
                        env->CallVoidMethod(callback, onTokenMethod, jchunk);
                        env->DeleteLocalRef(jchunk);
                    }
                }
            }
        }

        llama_batch next_batch = llama_batch_get_one(&new_tok, 1);
        if (llama_decode(g_ctx, next_batch) != 0) break;
    }

    return env->NewStringUTF(accumulated.c_str());
}
