package com.example.haku

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceResult
import com.google.mediapipe.tasks.core.OutputHandler
import kotlinx.coroutines.*
import java.io.File
import java.io.FileNotFoundException

/**
 * 🤖 MediaPipe GenAI LLM Bridge
 * 
 * ใช้ MediaPipe Tasks GenAI สำหรับรันโมเดล LiteRT (.task)
 * รองรับโมเดล: Gemma-3, Phi-4, Qwen ผ่าน LiteRT format
 * 
 * ข้อดี:
 * - ไม่ต้อง compile native library (C++)
 * - All-in-one: มี tokenizer ในตัว
 * - รองรับ GPU acceleration ผ่าน LiteRT
 */
class MediaPipeLLMBridge(private val context: Context) {
    
    companion object {
        private const val TAG = "MediaPipeLLM"
        
        @Volatile
        private var instance: MediaPipeLLMBridge? = null
        
        fun getInstance(context: Context): MediaPipeLLMBridge {
            return instance ?: synchronized(this) {
                instance ?: MediaPipeLLMBridge(context.applicationContext).also { 
                    instance = it 
                }
            }
        }
    }
    
    private var llmInference: LlmInference? = null
    private var currentModelPath: String? = null
    
    val isInitialized: Boolean
        get() = llmInference != null
    
    /**
     * 📥 โหลดโมเดล MediaPipe (.task file)
     * 
     * @param modelPath Path ไปยังไฟล์ .task
     * @param maxTokens จำนวน token สูงสุด (default: 1024)
     * @param temperature ค่าความสร้างสรรค์ (0.0 - 1.0, default: 0.7)
     * @return true ถ้าโหลดสำเร็จ
     */
    suspend fun loadModel(
        modelPath: String,
        maxTokens: Int = 1024,
        temperature: Float = 0.7f
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            Log.i(TAG, "📥 Loading MediaPipe model: $modelPath")
            
            // ตรวจสอบไฟล์
            val modelFile = File(modelPath)
            if (!modelFile.exists()) {
                Log.e(TAG, "❌ Model file not found: $modelPath")
                return@withContext false
            }
            
            // ปิดโมเดลเก่าถ้ามี
            unloadModel()
            
            // สร้าง LlmInference
            val options = LlmInference.LlmInferenceOptions.builder()
                .setModelPath(modelPath)
                .setMaxTokens(maxTokens)
                .setTemperature(temperature)
                .build()
            
            llmInference = LlmInference.createFromOptions(context, options)
            currentModelPath = modelPath
            
            Log.i(TAG, "✅ MediaPipe model loaded successfully")
            true
            
        } catch (e: FileNotFoundException) {
            Log.e(TAG, "❌ Model file not found: ${e.message}")
            false
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to load MediaPipe model: ${e.message}")
            e.printStackTrace()
            false
        }
    }
    
    /**
     * 💬 Generate text แบบ synchronous
     * 
     * @param prompt ข้อความ input
     * @return ข้อความที่สร้าง
     */
    suspend fun generate(prompt: String): String = withContext(Dispatchers.IO) {
        if (llmInference == null) {
            Log.e(TAG, "❌ Model not loaded")
            return@withContext ""
        }
        
        try {
            Log.d(TAG, "🤖 Generating with MediaPipe...")
            
            val result = llmInference?.generateResponse(prompt)
            
            Log.d(TAG, "✅ Generated ${result?.length ?: 0} chars")
            result ?: ""
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Generation failed: ${e.message}")
            e.printStackTrace()
            ""
        }
    }
    
    /**
     * 💬 Generate text แบบ streaming
     * 
     * @param prompt ข้อความ input
     * @param onToken callback สำหรับแต่ละ token
     */
    suspend fun generateStream(
        prompt: String,
        onToken: (String) -> Unit
    ) = withContext(Dispatchers.IO) {
        if (llmInference == null) {
            Log.e(TAG, "❌ Model not loaded")
            return@withContext
        }
        
        try {
            Log.d(TAG, "🤖 Generating with MediaPipe (streaming)...")
            
            val outputHandler = OutputHandler<LlmInferenceResult> { result ->
                val text = result.results.firstOrNull()?.outputText ?: ""
                onToken(text)
            }
            
            llmInference?.generateResponseAsync(prompt, outputHandler)
            
        } catch (e: Exception) {
            Log.e(TAG, "❌ Streaming generation failed: ${e.message}")
            e.printStackTrace()
        }
    }
    
    /**
     * 🗑️ ปิดโมเดลและปล่อยหน่วยความจำ
     */
    fun unloadModel() {
        try {
            llmInference?.close()
            llmInference = null
            currentModelPath = null
            Log.i(TAG, "🗑️ MediaPipe model unloaded")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error unloading model: ${e.message}")
        }
    }
    
    /**
     * 📊 ข้อมูลโมเดล
     */
    fun getModelInfo(): Map<String, Any?> {
        return mapOf(
            "initialized" to isInitialized,
            "modelPath" to currentModelPath,
            "backend" to "MediaPipe GenAI"
        )
    }
}
