# google_mlkit_text_recognition references the optional script-specific
# recognizers; only the Latin one is bundled, so silence the missing ones.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# ONNX Runtime's native code looks up these Java classes/methods by name via JNI;
# R8 renaming or removing them aborts the app on the first inference.
-keep class ai.onnxruntime.** { *; }
-keep class com.masicai.flutteronnxruntime.** { *; }
