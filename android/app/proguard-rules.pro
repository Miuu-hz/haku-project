# MediaPipe ProGuard Rules - Comprehensive
# ป้องกัน R8 ลบ classes ที่ MediaPipe ต้องการ

# ============================================================================
# 1. AutoValue (สำคัญมากสำหรับ MediaPipe)
# ============================================================================
-keep class com.google.auto.value.AutoValue { *; }
-keep class com.google.auto.value.AutoValue$Builder { *; }
-keep class com.google.auto.value.** { *; }
-keep @com.google.auto.value.AutoValue class * { *; }
-keep @com.google.auto.value.AutoValue.Builder class * { *; }
-keepclassmembers @com.google.auto.value.AutoValue class * { *; }
-keepclassmembers @com.google.auto.value.AutoValue.Builder class * { *; }

# ============================================================================
# 2. MediaPipe Framework Image (All Classes)
# ============================================================================
-keep class com.google.mediapipe.framework.image.** { *; }
-keep class com.google.mediapipe.framework.image.MPImage { *; }
-keep class com.google.mediapipe.framework.image.MPImageProperties { *; }
-keep class com.google.mediapipe.framework.image.BitmapExtractor { *; }
-keep class com.google.mediapipe.framework.image.ByteBufferExtractor { *; }
-keep class com.google.mediapipe.framework.image.MediaImageExtractor { *; }
-keep class com.google.mediapipe.framework.image.**$* { *; }

# ============================================================================
# 3. MediaPipe Framework (All)
# ============================================================================
-keep class com.google.mediapipe.framework.** { *; }
-keep class com.google.mediapipe.framework.*$* { *; }

# ============================================================================
# 4. MediaPipe Tasks GenAI
# ============================================================================
-keep class com.google.mediapipe.tasks.genai.** { *; }
-keep class com.google.mediapipe.tasks.genai.llminference.** { *; }
-keep class com.google.mediapipe.tasks.genai.llminference.*$* { *; }
-keepclassmembers class com.google.mediapipe.tasks.genai.llminference.* { *; }
-keepclassmembers class com.google.mediapipe.tasks.genai.llminference.*$* { *; }

# ============================================================================
# 5. MediaPipe Tasks Core
# ============================================================================
-keep class com.google.mediapipe.tasks.core.** { *; }

# ============================================================================
# 6. Native Methods
# ============================================================================
-keepclasseswithmembernames class * {
    native <methods>;
}

# ============================================================================
# 7. Constructors
# ============================================================================
-keepclasseswithmembers class * {
    public <init>(...);
}

# ============================================================================
# 8. Annotations
# ============================================================================
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod
-keepattributes RuntimeVisibleAnnotations
-keepattributes RuntimeInvisibleAnnotations
-keepattributes RuntimeVisibleParameterAnnotations
-keepattributes RuntimeInvisibleParameterAnnotations
-keepattributes MethodParameters

# ============================================================================
# 9. Don't warn about missing dependencies
# ============================================================================
-dontwarn com.google.auto.value.**
-dontwarn com.google.mediapipe.framework.image.**
