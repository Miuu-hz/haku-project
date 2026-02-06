package com.example.haku

import android.content.Context
import android.util.Log
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import kotlinx.coroutines.*
import java.io.File
import java.io.FileNotFoundException

/**
 * 🤖 MediaPipe GenAI LLM Bridge
 * 
 * ใช้ MediaPipe Tasks GenAI สำหรับรันโมเดล LiteRT (.task)
 * รองรับโมเดล: Gemma-3, Phi-4, Qwen ผ่าน LiteRT format
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
     * @return true ถ้าโหลดสำเร็จ
     */
    suspend fun loadModel(
        modelPath: String,
        maxTokens: Int = 1024
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            Log.i(TAG, "📥 Loading MediaPipe model: $modelPath")
            
            val modelFile = File(modelPath)
            if (!modelFile.exists()) {
                Log.e(TAG, "❌ Model file not found: $modelPath")
                return@withContext false
            }
            
            unloadModel()
            
            val options = LlmInference.LlmInferenceOptions.builder()
                .setModelPath(modelPath)
                .setMaxTokens(maxTokens)
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
     * 💬 Generate text (Synchronous)
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
     * 💬 Generate text with Streaming
     * 
     * Note: MediaPipe 0.10.20 - ใช้ generateResponse() แล้ว simulate streaming
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
            
            val fullResult = llmInference?.generateResponse(prompt) ?: ""
            
            // Simulate streaming by sending chunks
            val chunkSize = 10
            var currentPos = 0
            while (currentPos < fullResult.length) {
                val endPos = minOf(currentPos + chunkSize, fullResult.length)
                val chunk = fullResult.substring(currentPos, endPos)
                onToken(chunk)
                currentPos = endPos
                delay(50) // Small delay to simulate streaming
            }
            
            Log.d(TAG, "✅ Streaming completed")
            
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
