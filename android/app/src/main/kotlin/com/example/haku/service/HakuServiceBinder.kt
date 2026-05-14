package com.example.haku.service

import android.os.Binder

/**
 * 🎗️ Service Binder สำหรับ MainActivity ↔ HakuForegroundService
 *
 * ให้ Activity bind เข้า Service เพื่อ:
 * - แชร์ LLM engine instance
 * - ตรวจสอบว่า service กำลังทำงานอะไรอยู่
 * - ส่งคำสั่งจาก Activity → Service
 */
class HakuServiceBinder(private val service: HakuForegroundService) : Binder() {

    fun getService(): HakuForegroundService = service

    /**
     * ตรวจสอบว่า service กำลังประมวลผล LLM อยู่หรือไม่
     */
    fun isProcessing(): Boolean = service.isProcessing

    /**
     * ขอ LLM engine instance จาก service (สำหรับ share กับ MainActivity)
     */
    fun getLLMEngine(): com.example.haku.LiteRTLMBridge? = service.getLLMEngine()
}
