package com.example.haku

import android.util.Log
import android.opengl.GLES20
import javax.microedition.khronos.egl.EGL10
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.egl.EGLContext
import javax.microedition.khronos.egl.EGLDisplay
import javax.microedition.khronos.egl.EGLSurface

/**
 * 🤖 LLMBridge - Kotlin wrapper สำหรับเรียก native LLM (llama.cpp)
 *
 * ทำหน้าที่เป็น bridge ระหว่าง Flutter MethodChannel -> JNI -> llama.cpp
 *
 * ⚠️ GPU Compatibility:
 * - Adreno GPU (Qualcomm): Vulkan shader มีปัญหา → force CPU-only
 * - Mali GPU (Samsung Exynos): ส่วนใหญ่ OK
 * - PowerVR: ยังไม่ทดสอบ
 */
object LLMBridge {

    private const val TAG = "HakuLLM"

    private var isNativeAvailable = false
    private var gpuRenderer: String? = null
    private var gpuVendor: String? = null
    
    // Native methods (จาก libhaku_llm.so)
    @JvmStatic
    external fun nativeLoadModel(modelPath: String, contextSize: Int, gpuLayers: Int): Boolean
    
    @JvmStatic
    external fun nativeGenerate(prompt: String, temperature: Float, maxTokens: Int): String
    
    @JvmStatic
    external fun nativeUnloadModel()
    
    @JvmStatic
    external fun nativeIsLoaded(): Boolean
    
    @JvmStatic
    external fun nativeGetModelInfo(): String
    
    // Load native library
    init {
        try {
            System.loadLibrary("haku_llm")
            isNativeAvailable = true
            Log.i(TAG, "✅ Native library loaded successfully")

            // ตรวจจับ GPU
            detectGpu()
        } catch (e: UnsatisfiedLinkError) {
            isNativeAvailable = false
            Log.e(TAG, "❌ Failed to load native library: ${e.message}")
            Log.e(TAG, "   LLM features will be unavailable")
        }
    }

    /**
     * 🎮 ตรวจจับ GPU renderer และ vendor
     */
    private fun detectGpu() {
        try {
            val egl = EGLContext.getEGL() as EGL10
            val display = egl.eglGetDisplay(EGL10.EGL_DEFAULT_DISPLAY)
            egl.eglInitialize(display, intArrayOf(0, 0))

            val configAttribs = intArrayOf(
                EGL10.EGL_RENDERABLE_TYPE, 4, // EGL_OPENGL_ES2_BIT
                EGL10.EGL_NONE
            )
            val configs = arrayOfNulls<EGLConfig>(1)
            val numConfigs = IntArray(1)
            egl.eglChooseConfig(display, configAttribs, configs, 1, numConfigs)

            if (numConfigs[0] > 0) {
                val contextAttribs = intArrayOf(
                    0x3098, 2, // EGL_CONTEXT_CLIENT_VERSION = 2
                    EGL10.EGL_NONE
                )
                val context = egl.eglCreateContext(display, configs[0], EGL10.EGL_NO_CONTEXT, contextAttribs)

                val surfaceAttribs = intArrayOf(
                    EGL10.EGL_WIDTH, 1,
                    EGL10.EGL_HEIGHT, 1,
                    EGL10.EGL_NONE
                )
                val surface = egl.eglCreatePbufferSurface(display, configs[0], surfaceAttribs)

                egl.eglMakeCurrent(display, surface, surface, context)

                gpuRenderer = GLES20.glGetString(GLES20.GL_RENDERER)
                gpuVendor = GLES20.glGetString(GLES20.GL_VENDOR)

                Log.i(TAG, "🎮 GPU Vendor: $gpuVendor")
                Log.i(TAG, "🎮 GPU Renderer: $gpuRenderer")

                // Cleanup
                egl.eglMakeCurrent(display, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_SURFACE, EGL10.EGL_NO_CONTEXT)
                egl.eglDestroySurface(display, surface)
                egl.eglDestroyContext(display, context)
                egl.eglTerminate(display)
            }
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ Could not detect GPU: ${e.message}")
        }
    }

    /**
     * 🎮 ตรวจสอบว่าเป็น Adreno GPU หรือไม่ (Qualcomm - มีปัญหา Vulkan)
     */
    fun isAdrenoGpu(): Boolean {
        return gpuRenderer?.contains("Adreno", ignoreCase = true) == true ||
               gpuVendor?.contains("Qualcomm", ignoreCase = true) == true
    }

    /**
     * 🎮 ตรวจสอบว่า GPU รองรับ Vulkan สำหรับ LLM หรือไม่
     *
     * ⚠️ Adreno GPU มีปัญหา Vulkan shader crash:
     * - "Failed to link shaders"
     * - "Pipeline create failed"
     * - SIGSEGV ตอน vkCmdBindPipeline
     */
    fun isGpuSafeForVulkan(): Boolean {
        // Adreno มีปัญหา Vulkan shader กับ llama.cpp
        if (isAdrenoGpu()) {
            Log.w(TAG, "⚠️ Adreno GPU detected - Vulkan may crash, recommend CPU-only")
            return false
        }
        return true
    }

    /**
     * 📊 ข้อมูล GPU
     */
    fun getGpuInfo(): Map<String, Any?> {
        return mapOf(
            "vendor" to gpuVendor,
            "renderer" to gpuRenderer,
            "isAdreno" to isAdrenoGpu(),
            "vulkanSafe" to isGpuSafeForVulkan()
        )
    }
    
    /**
     * ✅ ตรวจสอบว่า native library พร้อมใช้งานหรือไม่
     */
    fun isAvailable(): Boolean = isNativeAvailable
    
    // =============================================================================
    // Public API สำหรับ MainActivity
    // =============================================================================
    
    /**
     * 📥 โหลดโมเดล GGUF
     *
     * @param modelPath Path ไปยังไฟล์ .gguf
     * @param contextSize ขนาด context (default: 4096)
     * @param gpuLayers จำนวน layers ที่ใช้ GPU (default: 0 = CPU only)
     * @return true ถ้าโหลดสำเร็จ
     *
     * ⚠️ ถ้าเป็น Adreno GPU จะ force CPU-only เพื่อป้องกัน Vulkan crash
     */
    fun loadModel(modelPath: String, contextSize: Int = 4096, gpuLayers: Int = 0): Boolean {
        if (!isNativeAvailable) {
            Log.e(TAG, "❌ Native library not available")
            return false
        }

        // ⚠️ Force CPU-only สำหรับ Adreno GPU (Vulkan crash)
        val effectiveGpuLayers = if (gpuLayers > 0 && !isGpuSafeForVulkan()) {
            Log.w(TAG, "⚠️ Adreno GPU detected! Forcing CPU-only mode to prevent Vulkan crash")
            Log.w(TAG, "   Requested gpuLayers=$gpuLayers → forcing to 0")
            0
        } else {
            gpuLayers
        }

        Log.i(TAG, "📥 Loading model: $modelPath")
        Log.i(TAG, "   contextSize=$contextSize, gpuLayers=$effectiveGpuLayers (requested: $gpuLayers)")

        return try {
            val result = nativeLoadModel(modelPath, contextSize, effectiveGpuLayers)
            if (result) {
                Log.i(TAG, "✅ Model loaded successfully")
                if (effectiveGpuLayers > 0) {
                    Log.i(TAG, "🎮 Using GPU acceleration ($effectiveGpuLayers layers)")
                } else {
                    Log.i(TAG, "🖥️ Using CPU-only mode")
                }
            } else {
                Log.e(TAG, "❌ Failed to load model")
            }
            result
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error loading model: ${e.message}")
            false
        }
    }
    
    /**
     * 💬 สร้างข้อความจาก prompt (synchronous)
     * 
     * @param prompt ข้อความ input
     * @param temperature ค่าความสร้างสรรค์ (0.0 - 1.0, default: 0.7)
     * @param maxTokens จำนวน token สูงสุด (default: 512)
     * @return ข้อความที่สร้าง
     */
    fun generate(prompt: String, temperature: Double = 0.7, maxTokens: Int = 512): String {
        if (!isNativeAvailable) {
            Log.e(TAG, "❌ Native library not available")
            return ""
        }
        
        if (!isModelLoaded()) {
            Log.e(TAG, "❌ Model not loaded")
            return ""
        }
        
        return try {
            Log.d(TAG, "🤖 Generating text...")
            val result = nativeGenerate(prompt, temperature.toFloat(), maxTokens)
            Log.d(TAG, "✅ Generation complete (${result.length} chars)")
            result
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error generating: ${e.message}")
            ""
        }
    }
    
    /**
     * 🗑️ ปิดโมเดลและปล่อยหน่วยความจำ
     */
    fun unloadModel() {
        if (!isNativeAvailable) {
            return
        }
        
        Log.i(TAG, "🗑️ Unloading model")
        try {
            nativeUnloadModel()
            Log.i(TAG, "✅ Model unloaded")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error unloading model: ${e.message}")
        }
    }
    
    /**
     * ✅ ตรวจสอบว่าโมเดลถูกโหลดแล้วหรือยัง
     */
    fun isModelLoaded(): Boolean {
        if (!isNativeAvailable) return false
        
        return try {
            nativeIsLoaded()
        } catch (e: Exception) {
            false
        }
    }
    
    /**
     * 📊 ข้อมูลโมเดลที่โหลดอยู่ (JSON string)
     */
    fun getModelInfo(): String {
        if (!isNativeAvailable) {
            return "{\"error\":\"Native library not available\"}"
        }
        
        return try {
            nativeGetModelInfo()
        } catch (e: Exception) {
            "{\"error\":\"${e.message}\"}"
        }
    }
}
