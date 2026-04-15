# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }

# Google Sign-In
-keep class com.google.android.gms.** { *; }

# Google Play Core (deferred components)
-dontwarn com.google.android.play.core.**

# Naver Map SDK
-keep class com.naver.maps.** { *; }

# Keep annotations
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
