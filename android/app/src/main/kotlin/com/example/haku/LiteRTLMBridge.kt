package com.example.haku

import android.content.Context
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.SamplerConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.CountDownLatch

/**
 * 🤖 LiteRT-LM Bridge — Google's modern on-device LLM runtime
 *
 * แทนที่ MediaPipeLLMBridge ที่ deprecated (reflection-based)
 * รองรับโมเดล:
 *   - Gemma 3 1B (.task legacy / .litertlm) — ปัจจุบัน
 *   - Gemma 4 E2B/E4B (.litertlm) — อนาคต พร้อม system instruction API
 *
 * ข้อดีหลักเทียบกับ MediaPipe:
 *   - True streaming (token-by-token จาก MessageCallback)
 *   - ไม่มี reflection — type-safe API ตรงๆ
 *   - GPU/CPU/NPU auto-fallback
 *   - Function calling built-in (สำหรับ Gemma 4 + FunctionGemma)
 *   - รองรับ system instruction — พร้อมสำหรับ Gemma 4
 */
class LiteRTLMBridge(private val context: Context) {

    companion object {
        private const val TAG = "LiteRTLM"

        @Volatile
        private var instance: LiteRTLMBridge? = null

        fun getInstance(context: Context): LiteRTLMBridge {
            return instance ?: synchronized(this) {
                instance ?: LiteRTLMBridge(context.applicationContext).also { instance = it }
            }
        }
    }

    private var engine: Engine? = null
    private var currentModelPath: String? = null
    private var currentSystemInstruction: String? = null
    private var _maxTokens: Int = 1024

    val isInitialized: Boolean get() = engine?.isInitialized() ?: false

    // ── Model Loading ──────────────────────────────────────────────────────────

    /**
     * 📥 โหลดโมเดล LiteRT-LM
     *
     * @param modelPath          path ไปยังไฟล์ .litertlm หรือ .task (legacy)
     * @param maxTokens          จำนวน token สูงสุด (default 1024)
     * @param systemInstruction  system prompt สำหรับ Gemma 4+ (optional)
     */
    suspend fun loadModel(
        modelPath: String,
        maxTokens: Int = 1024,
        systemInstruction: String? = null,
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            Log.i(TAG, "📥 กำลังโหลดโมเดล: $modelPath")

            if (!File(modelPath).exists()) {
                Log.e(TAG, "❌ ไม่พบไฟล์โมเดล: $modelPath")
                return@withContext false
            }

            unloadModel()
            _maxTokens = maxTokens
            currentSystemInstruction = systemInstruction

            val config = EngineConfig(
                modelPath = modelPath,
                backend = Backend.GPU(),
                maxNumTokens = maxTokens,
            )

            engine = Engine(config)
            engine!!.initialize()

            currentModelPath = modelPath
            Log.i(TAG, "✅ โหลดโมเดลสำเร็จ — maxTokens=$maxTokens systemInstruction=${systemInstruction != null}")
            true

        } catch (e: Exception) {
            Log.e(TAG, "❌ โหลดโมเดลล้มเหลว: ${e.message}")
            unloadModel()
            false
        }
    }

    // ── System Instruction (Gemma 4 ready) ────────────────────────────────────

    /**
     * 🔧 ตั้ง system instruction ใหม่ — ไม่ต้อง reload โมเดล
     * ใช้สำหรับ upgrade ไป Gemma 4 ที่ต้องการ system prompt
     */
    fun setSystemInstruction(instruction: String?) {
        currentSystemInstruction = instruction
        Log.i(TAG, "🔧 system instruction: ${instruction?.take(60)}...")
    }

    // ── Conversation Factory ───────────────────────────────────────────────────

    /**
     * สร้าง Conversation ใหม่สำหรับแต่ละ request
     *
     * Haku จัดการ history ที่ Dart side ด้วย LeanContext
     * → ส่ง full prompt ทุกครั้ง → conversation stateless ต่อ request
     */
    private fun newConversation(): Conversation? {
        val eng = engine ?: return null

        val sampler = SamplerConfig(topK = 40, topP = 0.95, temperature = 0.8, seed = 0)

        val config = ConversationConfig(
            systemInstruction = currentSystemInstruction?.let { Contents.of(it) },
            samplerConfig = sampler,
        )

        return try {
            eng.createConversation(config)
        } catch (e: Exception) {
            Log.e(TAG, "❌ สร้าง Conversation ล้มเหลว: ${e.message}")
            null
        }
    }

    // ── Inference ─────────────────────────────────────────────────────────────

    /**
     * 💬 Generate แบบ blocking — คืน full response
     * ใช้สำหรับ MethodChannel "generate" จาก Dart
     */
    suspend fun generate(prompt: String): String = withContext(Dispatchers.IO) {
        if (!isInitialized) {
            Log.e(TAG, "❌ ยังไม่ได้โหลดโมเดล")
            return@withContext ""
        }

        val conversation = newConversation() ?: return@withContext ""

        return@withContext try {
            val result = StringBuilder()
            val latch = CountDownLatch(1)

            conversation.sendMessageAsync(prompt, object : MessageCallback {
                override fun onMessage(message: com.google.ai.edge.litertlm.Message) {
                    result.append(message.toString())
                }
                override fun onDone() {
                    latch.countDown()
                }
                override fun onError(throwable: Throwable) {
                    Log.e(TAG, "❌ inference error: ${throwable.message}")
                    latch.countDown()
                }
            })

            latch.await()
            conversation.close()
            result.toString()

        } catch (e: Exception) {
            Log.e(TAG, "❌ generate ล้มเหลว: ${e.message}")
            conversation.close()
            ""
        }
    }

    /**
     * 💬 Generate แบบ true streaming — callback ทุก token จริงๆ
     * ต่างจาก MediaPipe เดิมที่ simulate streaming โดย chunk ผลลัพธ์
     */
    suspend fun generateStream(
        prompt: String,
        onToken: (String) -> Unit,
        onDone: () -> Unit = {},
    ) = withContext(Dispatchers.IO) {
        if (!isInitialized) {
            Log.e(TAG, "❌ ยังไม่ได้โหลดโมเดล")
            return@withContext
        }

        val conversation = newConversation() ?: return@withContext

        try {
            val latch = CountDownLatch(1)

            conversation.sendMessageAsync(prompt, object : MessageCallback {
                override fun onMessage(message: com.google.ai.edge.litertlm.Message) {
                    onToken(message.toString())
                }
                override fun onDone() {
                    onDone()
                    latch.countDown()
                }
                override fun onError(throwable: Throwable) {
                    Log.e(TAG, "❌ streaming error: ${throwable.message}")
                    latch.countDown()
                }
            })

            latch.await()
            conversation.close()

        } catch (e: Exception) {
            Log.e(TAG, "❌ generateStream ล้มเหลว: ${e.message}")
            conversation.close()
        }
    }

    // ── Lifecycle ──────────────────────────────────────────────────────────────

    /**
     * 🗑️ ปิด Engine และคืน memory
     */
    fun unloadModel() {
        try {
            engine?.close()
            engine = null
            currentModelPath = null
            Log.i(TAG, "🗑️ Unload โมเดลแล้ว")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Unload ล้มเหลว: ${e.message}")
        }
    }

    fun getModelInfo(): Map<String, Any?> = mapOf(
        "initialized"          to isInitialized,
        "modelPath"            to currentModelPath,
        "backend"              to "LiteRT-LM",
        "hasSystemInstruction" to (currentSystemInstruction != null),
        "status"               to if (isInitialized) "Ready" else "Not loaded",
    )
}
