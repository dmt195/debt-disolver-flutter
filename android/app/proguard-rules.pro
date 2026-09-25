# Release shrinking (R8 full mode) rules the libraries don't ship themselves.

# WorkManager 2.7 (pulled in by the ads SDK) creates its Room database
# reflectively from WorkDatabase_Impl; Room 2.2's own rules don't keep the
# constructor in full mode, so the app crashed on launch.
-keep class * extends androidx.room.RoomDatabase { <init>(); }

# flutter_local_notifications stores scheduled notifications with Gson,
# which needs the generic signatures and its model classes intact.
-keep class com.dexterous.** { *; }
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken
