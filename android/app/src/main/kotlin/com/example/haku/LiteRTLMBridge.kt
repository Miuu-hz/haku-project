package com.example.haku

import android.content.Context
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Conversation
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.ExperimentalApi
import com.google.ai.edge.litertlm.ExperimentalFlags
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.SamplerConfig
import com.google.ai.edge.litertlm.ToolProvider
import com.google.ai.edge.litertlm.ToolSet
import com.google.ai.edge.litertlm.tool
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
    private var _supportImage: Boolean = false
    private var _temperature: Double = 0.8
    private var _topK: Int = 40
    private var _topP: Double = 0.95

    // Stateful conversation — เก็บ KV cache ข้ามรอบ (ต่อ session)
    private var currentConversation: Conversation? = null

    // Tools สำหรับ function calling (Gemma 4)
    private var _tools: List<ToolProvider> = emptyList()

    // accelerator ที่ใช้อยู่ — CPU / GPU / NPU
    private var _currentAccelerator: String = "GPU"

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
        accelerator: String = "GPU",
        supportImage: Boolean = false,
    ): Boolean = withContext(Dispatchers.IO) {
        try {
            Log.i(TAG, "📥 กำลังโหลดโมเดล: $modelPath (accelerator=$accelerator)")

            if (!File(modelPath).exists()) {
                Log.e(TAG, "❌ ไม่พบไฟล์โมเดล: $modelPath")
                return@withContext false
            }

            unloadModel()
            _maxTokens = maxTokens
            _supportImage = supportImage
            currentSystemInstruction = systemInstruction

            val backend: Backend = when (accelerator.uppercase()) {
                "NPU" -> Backend.NPU(nativeLibraryDir = context.applicationInfo.nativeLibraryDir)
                "CPU" -> Backend.CPU()
                else  -> Backend.GPU()  // default = GPU
            }
            Log.i(TAG, "🎯 backend: $accelerator")

            val config = EngineConfig(
                modelPath = modelPath,
                backend = backend,
                visionBackend = if (supportImage) Backend.GPU() else null,
                maxNumTokens = maxTokens,
                cacheDir = context.getExternalFilesDir(null)?.absolutePath,
            )

            engine = Engine(config)
            engine!!.initialize()

            currentModelPath = modelPath
            _currentAccelerator = accelerator.uppercase()
            Log.i(TAG, "✅ โหลดโมเดลสำเร็จ — backend=$_currentAccelerator maxTokens=$maxTokens")
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
     * รีเซ็ต currentConversation เพราะ SI เปลี่ยน → KV cache เก่าใช้ไม่ได้
     */
    fun setSystemInstruction(instruction: String?) {
        currentSystemInstruction = instruction
        resetConversation()
        Log.i(TAG, "🔧 system instruction: ${instruction?.take(60)}...")
    }

    /**
     * 🔄 รีเซ็ต Conversation — เริ่ม session ใหม่ (ลบ KV cache เก่า)
     * เรียกเมื่อผู้ใช้เริ่มสนทนาใหม่หรือ system instruction เปลี่ยน
     */
    fun resetConversation() {
        try {
            currentConversation?.close()
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ ปิด conversation เก่าล้มเหลว (อาจปิดแล้ว): ${e.message}")
        }
        currentConversation = null
        Log.i(TAG, "🔄 Conversation รีเซ็ตแล้ว")
    }

    // ── Function Calling Tools ─────────────────────────────────────────────────

    /**
     * 🛠️ ตั้ง ToolSet สำหรับ function calling — รีเซ็ต conversation อัตโนมัติ
     *
     * เรียกก่อน loadModel หรือหลัง loadModel ก็ได้
     * ถ้าเรียกหลัง loadModel → conversation จะถูกสร้างใหม่พร้อม tools ในรอบถัดไป
     */
    fun setTools(toolSet: ToolSet?) {
        _tools = if (toolSet != null) listOf(tool(toolSet)) else emptyList()
        resetConversation()
        Log.i(TAG, "🛠️ tools: ${_tools.size} ToolProvider(s) set")
    }

    /**
     * 🔧 ตั้งค่า sampler parameters — ไม่ต้อง reload โมเดล
     */
    fun setSamplerParams(temperature: Double? = null, topK: Int? = null, topP: Double? = null) {
        temperature?.let { _temperature = it }
        topK?.let { _topK = it }
        topP?.let { _topP = it }
        Log.i(TAG, "🔧 sampler: temp=$_temperature, topK=$_topK, topP=$_topP")
    }

    // ── Conversation Management ────────────────────────────────────────────────

    /**
     * ดึง/สร้าง Conversation ปัจจุบัน (lazy)
     *
     * Stateful: เก็บ KV cache ข้ามรอบ → inference เร็วขึ้นใน session เดียวกัน
     * เรียก resetConversation() เพื่อเริ่ม session ใหม่
     * ถ้า _tools ไม่ว่าง → เปิด enableConversationConstrainedDecoding สำหรับ function calling
     */
    @OptIn(ExperimentalApi::class)
    private fun getOrCreateConversation(): Conversation? {
        currentConversation?.let { return it }

        val eng = engine ?: return null
        // ปิด session เก่าก่อนสร้างใหม่ (บาง device รองรับแค่ session เดียว)
        try { currentConversation?.close() } catch (_: Exception) {}

        val sampler = SamplerConfig(topK = _topK, topP = _topP, temperature = _temperature, seed = 0)
        val hasTools = _tools.isNotEmpty()

        // ต้อง set ExperimentalFlags ก่อน createConversation (global flag)
        if (hasTools) ExperimentalFlags.enableConversationConstrainedDecoding = true

        val config = ConversationConfig(
            systemInstruction = currentSystemInstruction?.let { Contents.of(it) },
            samplerConfig = sampler,
            tools = _tools,
        )

        return try {
            eng.createConversation(config).also {
                currentConversation = it
                if (hasTools) ExperimentalFlags.enableConversationConstrainedDecoding = false
                Log.i(TAG, "💬 Conversation สร้างแล้ว (tools=${_tools.size})")
            }
        } catch (e: Exception) {
            if (hasTools) ExperimentalFlags.enableConversationConstrainedDecoding = false
            Log.e(TAG, "❌ สร้าง Conversation ล้มเหลว: ${e.message}")
            null
        }
    }

    /** สร้าง Conversation แบบ one-shot (stateless) — ไม่บันทึกใน currentConversation */
    private fun newOneshotConversation(): Conversation? {
        val eng = engine ?: return null
        // ปิด conversation เก่าก่อนสร้างใหม่ (engine รองรับ session เดียว)
        try { currentConversation?.close() } catch (_: Exception) {}
        currentConversation = null

        val sampler = SamplerConfig(topK = _topK, topP = _topP, temperature = _temperature, seed = 0)
        val config = ConversationConfig(
            systemInstruction = currentSystemInstruction?.let { Contents.of(it) },
            samplerConfig = sampler,
        )
        return try {
            eng.createConversation(config)
        } catch (e: Exception) {
            Log.e(TAG, "❌ สร้าง one-shot Conversation ล้มเหลว: ${e.message}")
            null
        }
    }

    // ── Inference ─────────────────────────────────────────────────────────────

    /**
     * 💬 Generate แบบ one-shot blocking — stateless (สร้าง Conversation ใหม่ทุกครั้ง)
     *
     * ใช้สำหรับ background tasks เช่น SecretChat, WorkerService
     * ที่ต้องการ isolated context ไม่เกี่ยวกับ session ปัจจุบัน
     */
    suspend fun generate(prompt: String): String = withContext(Dispatchers.IO) {
        if (!isInitialized) {
            Log.e(TAG, "❌ ยังไม่ได้โหลดโมเดล")
            return@withContext ""
        }

        val conversation = newOneshotConversation() ?: return@withContext ""

        return@withContext try {
            val result = StringBuilder()
            val latch = CountDownLatch(1)

            conversation.sendMessageAsync(prompt, object : MessageCallback {
                override fun onMessage(message: com.google.ai.edge.litertlm.Message) {
                    result.append(message.toString())
                }
                override fun onDone() { latch.countDown() }
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
     * 💬 Generate แบบ stateful blocking — ใช้ KV cache ต่อ session
     *
     * เรียกเมื่อ user ส่งข้อความในหน้า Chat ปกติ
     * ส่งแค่ user message (ไม่มี history ใน string) — Conversation จัดการ context เอง
     * เรียก resetConversation() ก่อนเมื่อเริ่ม session ใหม่
     */
    suspend fun generateTurn(userMessage: String): String = withContext(Dispatchers.IO) {
        if (!isInitialized) {
            Log.e(TAG, "❌ ยังไม่ได้โหลดโมเดล")
            return@withContext ""
        }

        val conversation = getOrCreateConversation() ?: return@withContext ""

        return@withContext try {
            val result = StringBuilder()
            val thought = StringBuilder()
            val latch = CountDownLatch(1)
            var inferenceError: String? = null

            conversation.sendMessageAsync(userMessage, object : MessageCallback {
                override fun onMessage(message: com.google.ai.edge.litertlm.Message) {
                    result.append(message.toString())
                    message.channels["thought"]?.let { thought.append(it) }
                }
                override fun onDone() { latch.countDown() }
                override fun onError(throwable: Throwable) {
                    inferenceError = throwable.message
                    latch.countDown()
                }
            })

            latch.await()

            if (inferenceError != null) {
                Log.e(TAG, "❌ generateTurn error: $inferenceError")
                resetConversation()
                ""
            } else {
                // Prepend thinking block ถ้ามี — UI (_ThinkingSection) จะ parse แล้วแสดงแยก
                val thinkingPrefix = if (thought.isNotEmpty()) "<thinking>${thought.toString().trim()}</thinking>" else ""
                thinkingPrefix + result.toString()
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ generateTurn ล้มเหลว: ${e.message}")
            resetConversation()
            ""
        }
    }

    /**
     * 🖼️ Generate แบบ stateful พร้อม image input — ใช้ KV cache ต่อ session
     *
     * ต้องโหลดโมเดลด้วย supportImage=true ก่อน (visionBackend=GPU ต้องตั้งตอน loadModel)
     * ถ้า supportImage=false จะ fallback ไป text-only โดยอัตโนมัติ
     *
     * imageBytesList — PNG bytes ของแต่ละรูป (Dart ส่ง Uint8List มาผ่าน MethodChannel)
     */
    suspend fun generateTurnWithImages(
        userMessage: String,
        imageBytesList: List<ByteArray>,
    ): String = withContext(Dispatchers.IO) {
        if (!isInitialized) {
            Log.e(TAG, "❌ ยังไม่ได้โหลดโมเดล")
            return@withContext ""
        }
        if (!_supportImage || imageBytesList.isEmpty()) {
            return@withContext generateTurn(userMessage)
        }

        val conversation = getOrCreateConversation() ?: return@withContext ""

        return@withContext try {
            val result = StringBuilder()
            val thought = StringBuilder()
            val latch = CountDownLatch(1)
            var inferenceError: String? = null

            val contents = mutableListOf<Content>()
            for (imageBytes in imageBytesList) {
                contents.add(Content.ImageBytes(imageBytes))
            }
            if (userMessage.trim().isNotEmpty()) {
                contents.add(Content.Text(userMessage))
            }

            conversation.sendMessageAsync(Contents.of(contents), object : MessageCallback {
                override fun onMessage(message: com.google.ai.edge.litertlm.Message) {
                    result.append(message.toString())
                    message.channels["thought"]?.let { thought.append(it) }
                }
                override fun onDone() { latch.countDown() }
                override fun onError(throwable: Throwable) {
                    inferenceError = throwable.message
                    latch.countDown()
                }
            })

            latch.await()

            if (inferenceError != null) {
                Log.e(TAG, "❌ generateTurnWithImages error: $inferenceError")
                resetConversation()
                ""
            } else {
                val thinkingPrefix = if (thought.isNotEmpty()) "<thinking>${thought.toString().trim()}</thinking>" else ""
                thinkingPrefix + result.toString()
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ generateTurnWithImages ล้มเหลว: ${e.message}")
            resetConversation()
            ""
        }
    }

    /**
     * 💬 Generate แบบ true streaming — callback ทุก token จริงๆ
     * ต่างจาก MediaPipe เดิมที่ simulate streaming โดย chunk ผลลัพธ์
     * ใช้ one-shot conversation (stateless) เพราะ streaming มักเป็น background call
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

        val conversation = newOneshotConversation() ?: return@withContext

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
     * 🗑️ ปิด Conversation + Engine และคืน memory
     */
    fun unloadModel() {
        resetConversation()
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
        "accelerator"          to _currentAccelerator,
        "supportsImage"        to _supportImage,
        "hasSystemInstruction" to (currentSystemInstruction != null),
        "hasActiveSession"     to (currentConversation != null),
        "status"               to if (isInitialized) "Ready ($currentAccelerator)" else "Not loaded",
    )

    private val currentAccelerator get() = _currentAccelerator
}
