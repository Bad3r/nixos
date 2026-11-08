#pragma once

#include <jni.h>
#include <jni_bind.h>
#include <string>

// The upstream ghidra-jni dependency is only used for Ghidra's logging API.
// Keep that bridge local so the extension can be built from public sources.
namespace ghidra::util {
class Msg {
  static void log(const char* level, const std::string& tag, const char* message) {
    jni::ThreadGuard guard;
    JNIEnv* env = jni::JniEnv::GetEnv();
    jclass cls = env->FindClass("ghidra/util/Msg");
    if (cls == nullptr) {
      return;
    }
    jmethodID method = env->GetStaticMethodID(
        cls, level, "(Ljava/lang/Object;Ljava/lang/Object;)V");
    if (method == nullptr) {
      env->DeleteLocalRef(cls);
      return;
    }
    jstring origin = env->NewStringUTF(tag.c_str());
    jstring text = origin == nullptr ? nullptr : env->NewStringUTF(message);
    if (text != nullptr) {
      env->CallStaticVoidMethod(cls, method, origin, text);
    }
    env->DeleteLocalRef(text);
    env->DeleteLocalRef(origin);
    env->DeleteLocalRef(cls);
    // A pending JNI exception is deliberately left for the Java caller.
  }

 public:
  static void trace(const std::string& tag, const char* message) { log("trace", tag, message); }
  static void debug(const std::string& tag, const char* message) { log("debug", tag, message); }
  static void info(const std::string& tag, const char* message) { log("info", tag, message); }
  static void warn(const std::string& tag, const char* message) { log("warn", tag, message); }
  static void error(const std::string& tag, const char* message) { log("error", tag, message); }
};
}
