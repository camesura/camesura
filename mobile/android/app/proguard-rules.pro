# ML Kit uses reflection over its internal classes/fields (e.g.
# com.google.android.gms.internal.mlkit_vision_*). R8 renames/strips those
# targets in release builds, which makes pose detection crash with
# "InputImageConverterError: java.lang.NullPointerException ... getClass()"
# (class names like zzmj/zzmr/InputImage entirely obfuscated). Keep them.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_common.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_mediapipe.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_pose.** { *; }
-keep class com.google.android.gms.internal.mlkit_pose_detection.** { *; }
-keepattributes Signature