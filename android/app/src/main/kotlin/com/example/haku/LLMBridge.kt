package com.example.haku

import android.util.Log

/**
 * 🤖 LLMBridge - Kotlin wrapper สำหรับเรียก native LLM (llama.cpp)
 * 
 * ทำหน้าที่เป็น bridge ระหว่าง Flutter MethodChannel -> JNI -> llama.cpp
 */
object LLMBridge {
    
    private const val TAG = "HakuLLM"
    
    private var isNativeAvailable = false
    
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
        } catch (e: UnsatisfiedLinkError) {
            isNativeAvailable = false
            Log.e(TAG, "❌ Failed to load native library: ${e.message}")
            Log.e(TAG, "   LLM features will be unavailable")
        }
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
     */
    fun loadModel(modelPath: String, contextSize: Int = 4096, gpuLayers: Int = 0): Boolean {
        if (!isNativeAvailable) {
            Log.e(TAG, "❌ Native library not available")
            return false
        }
        
        Log.i(TAG, "📥 Loading model: $modelPath")
        return try {
            val result = nativeLoadModel(modelPath, contextSize, gpuLayers)
            if (result) {
                Log.i(TAG, "✅ Model loaded successfully")
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
