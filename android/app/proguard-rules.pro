# R8 release shrinking rules for LidaPay.
#
# The Flutter engine and most plugins ship their own consumer rules. These
# entries cover the reflection/JSON paths that otherwise break silently only
# in release builds.

# Flutter embedding and deferred components.
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# flutter_local_notifications deserialises scheduled notifications with GSON.
-keep class com.dexterous.** { *; }
-keep class com.google.gson.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# Firebase Messaging background handler is looked up by name from the
# manifest-merged service.
-keep class com.google.firebase.messaging.** { *; }
-keep class * extends com.google.firebase.messaging.FirebaseMessagingService

# local_auth / biometric fragments are instantiated reflectively.
-keep class androidx.biometric.** { *; }
-keep class io.flutter.plugins.localauth.** { *; }

# Geolocator and geocoding use platform channels only; keep their plugin
# registrants so the generated registrant can still resolve them.
-keep class com.baseflow.** { *; }
