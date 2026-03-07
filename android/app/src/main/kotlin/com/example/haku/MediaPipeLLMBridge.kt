package com.example.haku

import android.content.Context
import android.util.Log
import kotlinx.coroutines.*
import java.io.File
import java.io.FileNotFoundException

/**
 * 🤖 MediaPipe GenAI LLM Bridge
 *
 * ใช้ MediaPipe Tasks GenAI สำหรับรันโมเดล LiteRT (.task)
 * รองรับโมเดล: Gemma-3, Phi-4, Qwen ผ่าน LiteRT format
 *
 * ⚠️ หมายเหตุ: MediaPipe LLM Inference ต้องการ native library
 * ที่อาจไม่พร้อมใช้งานบนทุกอุปกรณ์ ระบบจะ fallback อัตโนมัติ
 */
class MediaPipeLLMBridge(private val context: Context) {

    companion object {
        private const val TAG = "MediaPipeLLM"

        @Volatile
        private var instance: MediaPipeLLMBridge? = null

        // ตรวจสอบว่า native library พร้อมใช้งานหรือไม่
        @Volatile
        private var isNativeAvailable: Boolean? = null

        fun getInstance(context: Context): MediaPipeLLMBridge {
            return instance ?: synchronized(this) {
                instance ?: MediaPipeLLMBridge(context.applicationContext).also {
                    instance = it
                }
            }
        }

        /**
         * ตรวจสอบว่า MediaPipe LLM พร้อมใช้งานหรือไม่
         * เรียกก่อนใช้งานเพื่อป้องกัน crash
         */
        fun checkAvailability(): Boolean {
            if (isNativeAvailable != null) return isNativeAvailable!!

            return try {
                // พยายามโหลด class เพื่อ trigger static initializer
                Class.forName("com.google.mediapipe.tasks.genai.llminference.LlmInference")
                isNativeAvailable = true
                Log.i(TAG, "✅ MediaPipe LLM native library is available")
                true
            } catch (e: UnsatisfiedLinkError) {
                isNativeAvailable = false
                Log.w(TAG, "⚠️ MediaPipe LLM native library not available: ${e.message}")
                false
            } catch (e: ClassNotFoundException) {
                isNativeAvailable = false
                Log.w(TAG, "⚠️ MediaPipe LLM class not found: ${e.message}")
                false
            } catch (e: ExceptionInInitializerError) {
                isNativeAvailable = false
                Log.w(TAG, "⚠️ MediaPipe LLM init failed: ${e.message}")
                false
            } catch (e: Exception) {
                isNativeAvailable = false
                Log.w(TAG, "⚠️ MediaPipe LLM check failed: ${e.message}")
                false
            }
        }
    }

    private var llmInference: Any? = null  // Use Any to avoid class loading
    private var currentModelPath: String? = null
    private var _isAvailable: Boolean = false
    private var _maxTokens: Int = 1024

    val isInitialized: Boolean
        get() = llmInference != null

    val isAvailable: Boolean
        get() = _isAvailable

    init {
        // ตรวจสอบความพร้อมใช้งานตอน init
        _isAvailable = checkAvailability()
    }

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
        // ตรวจสอบว่า native library พร้อมใช้งาน
        if (!_isAvailable) {
            Log.w(TAG, "⚠️ MediaPipe LLM not available, skipping model load")
            return@withContext false
        }

        try {
            Log.i(TAG, "📥 Loading MediaPipe model: $modelPath")

            val modelFile = File(modelPath)
            if (!modelFile.exists()) {
                Log.e(TAG, "❌ Model file not found: $modelPath")
                return@withContext false
            }

            unloadModel()

            // สร้าง LlmInference ผ่าน reflection เพื่อหลีกเลี่ยง class loading issues
            val llmClass = Class.forName("com.google.mediapipe.tasks.genai.llminference.LlmInference")
            val optionsClass = Class.forName("com.google.mediapipe.tasks.genai.llminference.LlmInference\$LlmInferenceOptions")
            val builderClass = Class.forName("com.google.mediapipe.tasks.genai.llminference.LlmInference\$LlmInferenceOptions\$Builder")

            // Get builder
            val builderMethod = optionsClass.getMethod("builder")
            val builder = builderMethod.invoke(null)

            // Set options
            val setModelPath = builderClass.getMethod("setModelPath", String::class.java)
            val setMaxTokens = builderClass.getMethod("setMaxTokens", Int::class.java)
            val buildMethod = builderClass.getMethod("build")

            setModelPath.invoke(builder, modelPath)
            setMaxTokens.invoke(builder, maxTokens)
            _maxTokens = maxTokens
            val options = buildMethod.invoke(builder)

            // Create LlmInference
            val createMethod = llmClass.getMethod("createFromOptions", Context::class.java, optionsClass)
            llmInference = createMethod.invoke(null, context, options)

            currentModelPath = modelPath

            Log.i(TAG, "✅ MediaPipe model loaded successfully")
            true

        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "❌ Native library not available: ${e.message}")
            _isAvailable = false
            false
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
     *
     * @param prompt ข้อความ input
     * @return ข้อความที่สร้าง หรือ empty string ถ้าไม่พร้อมใช้งาน
     */
    suspend fun generate(prompt: String): String = withContext(Dispatchers.IO) {
        if (!_isAvailable) {
            Log.w(TAG, "⚠️ MediaPipe LLM not available")
            return@withContext ""
        }

        if (llmInference == null) {
            Log.e(TAG, "❌ Model not loaded")
            return@withContext ""
        }

        try {
            // ป้องกัน SIGABRT: MediaPipe crash ด้วย JNI error แทน exception เมื่อ input ยาวเกิน
            // ใช้ 1.5 chars/token เป็น conservative estimate สำหรับ Thai/English mixed
            val estimatedTokens = (prompt.length / 1.5).toInt()
            val inputBudget = _maxTokens - 100 // เผื่อ output 100 tokens
            if (estimatedTokens > inputBudget) {
                Log.w(TAG, "⚠️ Prompt too long (~$estimatedTokens est. tokens > $inputBudget budget), refusing to prevent SIGABRT crash")
                return@withContext ""
            }

            Log.d(TAG, "🤖 Generating with MediaPipe... (~$estimatedTokens est. tokens)")

            // Use reflection to call generateResponse
            val generateMethod = llmInference!!.javaClass.getMethod("generateResponse", String::class.java)
            val result = generateMethod.invoke(llmInference, prompt) as? String

            Log.d(TAG, "✅ Generated ${result?.length ?: 0} chars")
            result ?: ""

        } catch (e: UnsatisfiedLinkError) {
            Log.e(TAG, "❌ Native library error: ${e.message}")
            _isAvailable = false
            ""
        } catch (e: Exception) {
            Log.e(TAG, "❌ Generation failed: ${e.message}")
            e.printStackTrace()
            ""
        }
    }

    /**
     * 💬 Generate text with Streaming
     *
     * Note: MediaPipe - ใช้ generateResponse() แล้ว simulate streaming
     *
     * @param prompt ข้อความ input
     * @param onToken callback สำหรับแต่ละ token
     */
    suspend fun generateStream(
        prompt: String,
        onToken: (String) -> Unit
    ) = withContext(Dispatchers.IO) {
        if (!_isAvailable) {
            Log.w(TAG, "⚠️ MediaPipe LLM not available for streaming")
            return@withContext
        }

        if (llmInference == null) {
            Log.e(TAG, "❌ Model not loaded")
            return@withContext
        }

        try {
            Log.d(TAG, "🤖 Generating with MediaPipe (streaming)...")

            // Generate full response first
            val result = generate(prompt)

            // Simulate streaming by sending chunks
            result.chunked(10).forEach { chunk ->
                onToken(chunk)
                delay(50) // Small delay for streaming effect
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
            if (llmInference != null) {
                val closeMethod = llmInference!!.javaClass.getMethod("close")
                closeMethod.invoke(llmInference)
            }
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
            "available" to isAvailable,
            "modelPath" to currentModelPath,
            "backend" to "MediaPipe GenAI",
            "status" to if (!_isAvailable) "Native library not available" else if (isInitialized) "Ready" else "Not loaded"
        )
    }
}
