# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Play Core (deferred components) - not used but referenced by Flutter
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Crypto / PointyCastle - prevent stripping encryption classes
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Google Sign In
-keep class com.google.android.gms.auth.** { *; }

# Flutter Secure Storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}
