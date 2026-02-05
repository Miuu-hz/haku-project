# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# MediaPipe GenAI - Keep all classes and native methods
-keep class com.google.mediapipe.** { *; }
-keep class com.google.mediapipe.tasks.** { *; }
-keep class com.google.mediapipe.tasks.genai.** { *; }
-keep class com.google.mediapipe.tasks.genai.llminference.** { *; }
-keepclassmembers class * {
    native <methods>;
}

# Keep JNI classes
-keepclasseswithmembernames class * {
    native <methods>;
}

# Haku LLM Bridge
-keep class com.example.haku.MediaPipeLLMBridge { *; }
-keep class com.example.haku.LLMBridge { *; }
