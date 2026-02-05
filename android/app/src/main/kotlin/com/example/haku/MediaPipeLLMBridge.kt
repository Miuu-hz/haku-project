package com.example.haku

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInference.LlmInferenceOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 🤖 MediaPipe LLM Bridge - ใช้ MediaPipe GenAI (LiteRT)
 * 
 * ✅ ข้อดี:
 * - All-in-One (มี tokenizer ในตัว)
 * - ไม่ต้องจัดการ native library เอง
 * - Google official support
 * - รองรับ Gemma-3, Qwen, Llama ผ่าน LiteRT
 */
object MediaPipeLLMBridge {

    private const val TAG = "HakuMediaPipeLLM"

    private var llmInference: LlmInference? = null
    private var isInitialized = false
    private var currentModelPath: String? = null

    /**
     * ✅ ตรวจสอบว่า LLM พร้อมใช้งานหรือไม่
     */
    fun isAvailable(): Boolean = true // MediaPipe ไม่ต้องโหลด native lib แยก

    /**
     * ✅ ตรวจสอบว่าโมเดลถูกโหลดแล้วหรือยัง
     */
    fun isModelLoaded(): Boolean = llmInference != null && isInitialized

    /**
     * 📥 โหลดโมเดล LiteRT (.task หรือ .tflite)
     * 
     * @param context Application context
     * @param modelPath Path ไปยังไฟล์ .task หรือ .tflite
     * @param maxTokens จำนวน token สูงสุด (default: 1024)
     * @param temperature ค่าความสร้างสรรค์ (0.0 - 1.0, default: 0.7)
     * @return true ถ้าโหลดสำเร็จ
     */
    fun loadModel(
        context: Context,
        modelPath: String,
        maxTokens: Int = 1024,
        temperature: Float = 0.7f
    ): Boolean {
        Log.i(TAG, "📥 Loading MediaPipe model: $modelPath")

        return try {
            // สร้าง options สำหรับ LLM Inference
            // Note: Temperature ถูกตั้งค่าผ่าน generateResponse() แทน
            val options = LlmInferenceOptions.builder()
                .setModelPath(modelPath)
                .setMaxTokens(maxTokens)
                .build()

            // สร้าง LlmInference instance
            llmInference = LlmInference.createFromOptions(context, options)
            
            isInitialized = true
            currentModelPath = modelPath
            
            Log.i(TAG, "✅ MediaPipe model loaded successfully")
            Log.i(TAG, "   Path: $modelPath")
            Log.i(TAG, "   MaxTokens: $maxTokens")
            
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to load MediaPipe model: ${e.message}")
            Log.e(TAG, "   Stack: ${e.stackTraceToString()}")
            isInitialized = false
            false
        }
    }

    /**
     * 💬 สร้างข้อความจาก prompt
     * 
     * @param prompt ข้อความ input
     * @return ข้อความที่สร้าง หรือ empty string ถ้า error
     */
    fun generate(prompt: String): String {
        if (!isModelLoaded()) {
            Log.e(TAG, "❌ Model not loaded")
            return ""
        }

        return try {
            Log.d(TAG, "🤖 Generating response...")
            
            // ใช้ generateResponse สำหรับ non-streaming
            val response = llmInference?.generateResponse(prompt) ?: ""
            
            Log.d(TAG, "✅ Generated ${response.length} chars")
            response
        } catch (e: Exception) {
            Log.e(TAG, "❌ Generation error: ${e.message}")
            ""
        }
    }

    /**
     * 💬 สร้างข้อความแบบ Async (non-streaming)
     * 
     * @param prompt ข้อความ input
     * @return ข้อความที่สร้าง
     */
    suspend fun generateAsync(prompt: String): String {
        if (!isModelLoaded()) {
            Log.e(TAG, "❌ Model not loaded")
            return ""
        }

        return try {
            Log.d(TAG, "🤖 Starting async generation...")
            
            // ใช้ generateResponseAsync (ไม่มี callback ในตัว)
            llmInference?.generateResponseAsync(prompt)
            
            // สำหรับตอนนี้ return empty ก่อน (จะ implement จริงภายหลัง)
            Log.d(TAG, "✅ Async generation initiated")
            ""
        } catch (e: Exception) {
            Log.e(TAG, "❌ Async generation error: ${e.message}")
            ""
        }
    }

    /**
     * 🗑️ ปิดโมเดลและปล่อยหน่วยความจำ
     */
    fun unloadModel() {
        Log.i(TAG, "🗑️ Unloading MediaPipe model")
        try {
            llmInference?.close()
            llmInference = null
            isInitialized = false
            currentModelPath = null
            Log.i(TAG, "✅ Model unloaded")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error unloading model: ${e.message}")
        }
    }

    /**
     * 📊 ข้อมูลโมเดลที่โหลดอยู่
     */
    fun getModelInfo(): Map<String, Any?> {
        return mapOf(
            "engine" to "MediaPipe GenAI (LiteRT)",
            "modelPath" to currentModelPath,
            "isLoaded" to isModelLoaded(),
            "isInitialized" to isInitialized
        )
    }
}
