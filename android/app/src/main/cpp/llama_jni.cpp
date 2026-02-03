/**
 * 🤖 llama_jni.cpp - JNI Bridge สำหรับ llama.cpp
 * 
 * Compatible with llama.cpp latest master (Jan 2026)
 * Uses new llama_vocab API
 */

#include <jni.h>
#include <string>
#include <vector>
#include <memory>
#include <mutex>
#include <thread>

// llama.cpp headers
#include "llama.h"

// Android log
#include <android/log.h>

#define LOG_TAG "HakuLLM"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGD(...) __android_log_print(ANDROID_LOG_DEBUG, LOG_TAG, __VA_ARGS__)

// =============================================================================
// Global State (singleton pattern)
// =============================================================================

struct LLMState {
    llama_model* model = nullptr;
    llama_context* ctx = nullptr;
    llama_sampler* sampler = nullptr;
    const llama_vocab* vocab = nullptr;  // New in latest llama.cpp
    std::mutex mutex;
    bool isLoaded = false;
    
    void reset() {
        if (sampler) {
            llama_sampler_free(sampler);
            sampler = nullptr;
        }
        if (ctx) {
            llama_free(ctx);
            ctx = nullptr;
        }
        if (model) {
            llama_model_free(model);
            model = nullptr;
        }
        vocab = nullptr;
        isLoaded = false;
    }
};

static LLMState g_state;

// =============================================================================
// Helper Functions
// =============================================================================

static std::string jstring_to_string(JNIEnv* env, jstring jstr) {
    if (!jstr) return "";
    const char* cstr = env->GetStringUTFChars(jstr, nullptr);
    std::string str(cstr ? cstr : "");
    env->ReleaseStringUTFChars(jstr, cstr);
    return str;
}

static void log_callback(enum ggml_log_level level, const char* text, void* user_data) {
    (void)user_data;
    switch (level) {
        case GGML_LOG_LEVEL_INFO:
            LOGI("llama: %s", text);
            break;
        case GGML_LOG_LEVEL_WARN:
            LOGI("llama warning: %s", text);
            break;
        case GGML_LOG_LEVEL_ERROR:
            LOGE("llama error: %s", text);
            break;
        default:
            LOGD("llama: %s", text);
            break;
    }
}

// Helper to add token to batch
static void batch_add_token(llama_batch& batch, llama_token token, llama_pos pos, std::vector<int32_t>& n_seq_id, bool logits) {
    int idx = batch.n_tokens;
    batch.token[idx] = token;
    batch.pos[idx] = pos;
    batch.n_seq_id[idx] = 1;
    batch.seq_id[idx] = n_seq_id.data();
    batch.logits[idx] = logits ? 1 : 0;
    batch.n_tokens++;
}

// =============================================================================
// JNI Methods
// =============================================================================

extern "C" {

/**
 * 📥 โหลดโมเดล GGUF
 */
JNIEXPORT jboolean JNICALL
Java_com_example_haku_LLMBridge_nativeLoadModel(
    JNIEnv* env,
    jclass clazz,
    jstring modelPath,
    jint contextSize,
    jint gpuLayers
) {
    std::lock_guard<std::mutex> lock(g_state.mutex);
    
    // Unload โมเดลเก่าถ้ามี
    g_state.reset();
    
    std::string path = jstring_to_string(env, modelPath);
    if (path.empty()) {
        LOGE("Model path is empty");
        return JNI_FALSE;
    }
    
    LOGI("Loading model: %s", path.c_str());
    
    // Set log callback
    llama_log_set(log_callback, nullptr);
    
    // Model parameters
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = gpuLayers;
    model_params.main_gpu = 0;
    
    // Load model
    g_state.model = llama_model_load_from_file(path.c_str(), model_params);
    if (!g_state.model) {
        LOGE("Failed to load model from: %s", path.c_str());
        return JNI_FALSE;
    }
    
    // Get vocab (new API)
    g_state.vocab = llama_model_get_vocab(g_state.model);
    if (!g_state.vocab) {
        LOGE("Failed to get vocab from model");
        g_state.reset();
        return JNI_FALSE;
    }
    
    LOGI("Model loaded, vocab size: %d", llama_vocab_n_tokens(g_state.vocab));
    
    // Context parameters
    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = contextSize;
    ctx_params.n_batch = 2048;
    ctx_params.n_ubatch = 512;
    
    // Auto-detect threads
    ctx_params.n_threads = std::min(4, (int)std::thread::hardware_concurrency());
    ctx_params.n_threads_batch = ctx_params.n_threads;
    
    LOGI("Creating context with %d threads", ctx_params.n_threads);
    
    // Create context
    g_state.ctx = llama_init_from_model(g_state.model, ctx_params);
    if (!g_state.ctx) {
        LOGE("Failed to create context");
        g_state.reset();
        return JNI_FALSE;
    }
    
    // Create sampler chain
    g_state.sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
    if (!g_state.sampler) {
        LOGE("Failed to create sampler");
        g_state.reset();
        return JNI_FALSE;
    }
    
    // Add samplers to chain
    llama_sampler_chain_add(g_state.sampler, llama_sampler_init_temp(0.7f));
    llama_sampler_chain_add(g_state.sampler, llama_sampler_init_top_p(0.95f, 1));
    llama_sampler_chain_add(g_state.sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(g_state.sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    
    g_state.isLoaded = true;
    LOGI("Model loaded successfully!");
    
    return JNI_TRUE;
}

/**
 * 💬 Generate text (synchronous)
 */
JNIEXPORT jstring JNICALL
Java_com_example_haku_LLMBridge_nativeGenerate(
    JNIEnv* env,
    jclass clazz,
    jstring prompt,
    jfloat temperature,
    jint maxTokens
) {
    std::lock_guard<std::mutex> lock(g_state.mutex);
    
    if (!g_state.isLoaded || !g_state.ctx || !g_state.model || !g_state.vocab) {
        LOGE("Model not loaded");
        return env->NewStringUTF("");
    }
    
    std::string prompt_str = jstring_to_string(env, prompt);
    if (prompt_str.empty()) {
        return env->NewStringUTF("");
    }
    
    LOGD("Generating with temp=%.2f, max_tokens=%d", temperature, maxTokens);
    
    // Tokenize prompt using vocab (new API)
    std::vector<llama_token> prompt_tokens;
    prompt_tokens.resize(prompt_str.length() + 16);
    
    int n_tokens = llama_tokenize(
        g_state.vocab,
        prompt_str.c_str(),
        prompt_str.length(),
        prompt_tokens.data(),
        prompt_tokens.size(),
        true,  // add special tokens
        true   // parse special
    );
    
    if (n_tokens < 0) {
        LOGE("Tokenization failed");
        return env->NewStringUTF("");
    }
    
    prompt_tokens.resize(n_tokens);
    LOGD("Prompt tokenized to %d tokens", n_tokens);
    
    // Create batch
    llama_batch batch = llama_batch_init(prompt_tokens.size(), 0, 1);
    
    // Add tokens to batch manually
    std::vector<int32_t> n_seq_id = {0};
    for (size_t i = 0; i < prompt_tokens.size(); i++) {
        bool is_last = (i == prompt_tokens.size() - 1);
        batch_add_token(batch, prompt_tokens[i], i, n_seq_id, is_last);
    }
    
    // Decode prompt
    int decode_result = llama_decode(g_state.ctx, batch);
    llama_batch_free(batch);
    
    if (decode_result != 0) {
        LOGE("Failed to decode prompt, error: %d", decode_result);
        return env->NewStringUTF("");
    }
    
    LOGD("Prompt decoded, generating response...");
    
    // Update sampler temperature if different
    if (temperature > 0 && g_state.sampler) {
        llama_sampler_free(g_state.sampler);
        g_state.sampler = llama_sampler_chain_init(llama_sampler_chain_default_params());
        llama_sampler_chain_add(g_state.sampler, llama_sampler_init_temp(temperature));
        llama_sampler_chain_add(g_state.sampler, llama_sampler_init_top_p(0.95f, 1));
        llama_sampler_chain_add(g_state.sampler, llama_sampler_init_top_k(40));
        llama_sampler_chain_add(g_state.sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));
    }
    
    // Generate tokens
    std::string response;
    llama_pos pos = prompt_tokens.size();
    
    for (int i = 0; i < maxTokens; i++) {
        // Sample next token
        llama_token new_token = llama_sampler_sample(g_state.sampler, g_state.ctx, -1);
        
        // Check for end of generation using vocab (new API)
        if (llama_vocab_is_eog(g_state.vocab, new_token)) {
            LOGD("End of generation token reached");
            break;
        }
        
        // Convert token to text using vocab (new API)
        char buf[256];
        int n = llama_token_to_piece(g_state.vocab, new_token, buf, sizeof(buf), 0, true);
        if (n > 0) {
            response.append(buf, n);
        }
        
        // Prepare next batch with single token
        llama_batch batch_next = llama_batch_init(1, 0, 1);
        batch_add_token(batch_next, new_token, pos++, n_seq_id, true);
        
        decode_result = llama_decode(g_state.ctx, batch_next);
        llama_batch_free(batch_next);
        
        if (decode_result != 0) {
            LOGE("Failed to decode token at pos %d", pos);
            break;
        }
    }
    
    LOGD("Generated %zu characters", response.length());
    
    return env->NewStringUTF(response.c_str());
}

/**
 * 🗑️ Unload model
 */
JNIEXPORT void JNICALL
Java_com_example_haku_LLMBridge_nativeUnloadModel(
    JNIEnv* env,
    jclass clazz
) {
    std::lock_guard<std::mutex> lock(g_state.mutex);
    LOGI("Unloading model");
    g_state.reset();
    LOGI("Model unloaded");
}

/**
 * ✅ Check if model is loaded
 */
JNIEXPORT jboolean JNICALL
Java_com_example_haku_LLMBridge_nativeIsLoaded(
    JNIEnv* env,
    jclass clazz
) {
    std::lock_guard<std::mutex> lock(g_state.mutex);
    return g_state.isLoaded ? JNI_TRUE : JNI_FALSE;
}

/**
 * 📊 Get model info
 */
JNIEXPORT jstring JNICALL
Java_com_example_haku_LLMBridge_nativeGetModelInfo(
    JNIEnv* env,
    jclass clazz
) {
    std::lock_guard<std::mutex> lock(g_state.mutex);
    
    if (!g_state.isLoaded || !g_state.model || !g_state.vocab) {
        return env->NewStringUTF("{\"loaded\":false}");
    }
    
    // Build JSON response
    std::string info = "{";
    info += "\"loaded\":true,";
    info += "\"vocab_size\":" + std::to_string(llama_vocab_n_tokens(g_state.vocab)) + ",";
    info += "\"context_size\":" + std::to_string(llama_n_ctx(g_state.ctx)) + ",";
    info += "\"embedding_size\":" + std::to_string(llama_model_n_embd(g_state.model)) + ",";
    info += "\"layer_count\":" + std::to_string(llama_model_n_layer(g_state.model));
    info += "}";
    
    return env->NewStringUTF(info.c_str());
}

} // extern "C"
