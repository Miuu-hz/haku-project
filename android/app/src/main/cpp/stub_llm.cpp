/**
 * 📝 stub_llm.cpp - Stub implementation สำหรับกรณีที่ยังไม่มี llama.cpp
 * 
 * ใช้เป็น fallback เมื่อยังไม่ได้ clone llama.cpp
 * จะคืนค่า error กลับไปให้ Flutter ทราบ
 */

#include <jni.h>
#include <android/log.h>

#define LOG_TAG "HakuLLM"
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)

extern "C" {

JNIEXPORT jboolean JNICALL
Java_com_example_haku_LLMBridge_nativeLoadModel(
    JNIEnv* env,
    jclass clazz,
    jstring modelPath,
    jint contextSize,
    jint gpuLayers
) {
    LOGE("llama.cpp not available. Please clone llama.cpp to android/app/src/main/cpp/llama.cpp");
    return JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_example_haku_LLMBridge_nativeGenerate(
    JNIEnv* env,
    jclass clazz,
    jstring prompt,
    jfloat temperature,
    jint maxTokens
) {
    LOGE("llama.cpp not available");
    return env->NewStringUTF("");
}

JNIEXPORT void JNICALL
Java_com_example_haku_LLMBridge_nativeUnloadModel(
    JNIEnv* env,
    jclass clazz
) {
    // Nothing to do
}

JNIEXPORT jboolean JNICALL
Java_com_example_haku_LLMBridge_nativeIsLoaded(
    JNIEnv* env,
    jclass clazz
) {
    return JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_example_haku_LLMBridge_nativeGetModelInfo(
    JNIEnv* env,
    jclass clazz
) {
    return env->NewStringUTF("{\"error\":\"llama.cpp not available\"}");
}

} // extern "C"
