#include <jni.h>
#include <string>
#include <vector>
#include <atomic>
#include <mutex>
#include <algorithm>
#include <chrono>
#include <android/log.h>
#include "llama.h"
#include "ggml-backend.h"

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

static jbyteArray to_jbyte_array(JNIEnv * env, const std::string & str) {
    jsize len = (jsize)str.size();
    jbyteArray arr = env->NewByteArray(len);
    if (arr && len > 0) {
        env->SetByteArrayRegion(arr, 0, len, reinterpret_cast<const jbyte *>(str.data()));
    }
    return arr;
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

    ggml_backend_dev_t cpu_devs[2] = { nullptr, nullptr };
    ggml_backend_dev_t cpu_dev = ggml_backend_dev_by_type(GGML_BACKEND_DEVICE_TYPE_CPU);
    if (cpu_dev) {
        cpu_devs[0] = cpu_dev;
        mparams.devices = cpu_devs;
    }

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
    int thr = std::max(2, std::min(4, (int)threads));
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

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_tomy_httnavicompanion_audio_LlamaNativeBridge_nativeGenerateBytes(
        JNIEnv * env,
        jobject /* thiz */,
        jbyteArray jpromptBytes,
        jobject callback) {
    std::lock_guard<std::mutex> lock(g_mutex);
    if (!g_model || !g_ctx || !g_smpl || !jpromptBytes) {
        return to_jbyte_array(env, "");
    }
    g_cancel.store(false);

    jsize plen = env->GetArrayLength(jpromptBytes);
    std::string prompt(plen, '\0');
    if (plen > 0) {
        env->GetByteArrayRegion(jpromptBytes, 0, plen, reinterpret_cast<jbyte *>(&prompt[0]));
    }

    const llama_vocab * vocab = llama_model_get_vocab(g_model);
    int max_toks = (int)prompt.size() + 64;
    std::vector<llama_token> tokens(max_toks);
    int n_tokens = llama_tokenize(vocab, prompt.c_str(), (int32_t)prompt.size(), tokens.data(), max_toks, true, true);
    if (n_tokens <= 0) {
        return to_jbyte_array(env, "");
    }

    int max_prompt = std::max(128, g_ctx_len - 128);
    if (n_tokens > max_prompt) {
        int keep_head = std::min(96, max_prompt / 3);
        int keep_tail = max_prompt - keep_head;
        std::copy(tokens.begin() + (n_tokens - keep_tail), tokens.begin() + n_tokens, tokens.begin() + keep_head);
        n_tokens = max_prompt;
    }
    int total_prompt = n_tokens;

    llama_kv_self_clear(g_ctx);
    llama_sampler_reset(g_smpl);

    auto start_tp = std::chrono::steady_clock::now();
    auto timed_out = [&]() {
        return std::chrono::duration_cast<std::chrono::seconds>(
            std::chrono::steady_clock::now() - start_tp
        ).count() >= 25;
    };

    for (int off = 0; off < total_prompt; ) {
        if (g_cancel.load() || timed_out()) break;
        int step = std::min(64, total_prompt - off);
        llama_batch batch = llama_batch_get_one(tokens.data() + off, step);
        if (llama_decode(g_ctx, batch) != 0) {
            LOGE("llama_decode prompt failed at off=%d", off);
            return to_jbyte_array(env, "");
        }
        off += step;
    }

    jmethodID onTokenBytesMethod = nullptr;
    if (callback) {
        jclass cls = env->GetObjectClass(callback);
        if (cls) {
            onTokenBytesMethod = env->GetMethodID(cls, "onTokenBytes", "([B)V");
            if (env->ExceptionCheck()) {
                env->ExceptionClear();
                onTokenBytesMethod = nullptr;
            }
            env->DeleteLocalRef(cls);
        }
    }

    std::string accumulated;
    std::string utf8_pending;
    int max_gen = std::min(128, std::max(32, g_ctx_len - total_prompt - 4));

    for (int i = 0; i < max_gen; ++i) {
        if (g_cancel.load() || timed_out()) break;
        llama_token new_tok = llama_sampler_sample(g_smpl, g_ctx, -1);
        if (llama_vocab_is_eog(vocab, new_tok)) break;

        char piece[64];
        int n = llama_token_to_piece(vocab, new_tok, piece, sizeof(piece), 0, true);
        if (n > 0) {
            utf8_pending.append(piece, n);
            size_t valid_len = utf8_pending.size();
            while (valid_len > 0) {
                unsigned char c = (unsigned char)utf8_pending[valid_len - 1];
                if ((c & 0x80) == 0) break;
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
                if (callback && onTokenBytesMethod) {
                    jbyteArray jbytes = to_jbyte_array(env, accumulated);
                    if (jbytes) {
                        env->CallVoidMethod(callback, onTokenBytesMethod, jbytes);
                        env->DeleteLocalRef(jbytes);
                        if (env->ExceptionCheck()) {
                            env->ExceptionClear();
                        }
                    }
                }
            }
        }

        llama_batch next_batch = llama_batch_get_one(&new_tok, 1);
        if (llama_decode(g_ctx, next_batch) != 0) break;
    }

    return to_jbyte_array(env, accumulated);
}
