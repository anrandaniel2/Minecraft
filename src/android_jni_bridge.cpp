// SPDX-License-Identifier: MIT

#include "android_jni_bridge.h"

#ifdef __ANDROID__

#include <godot_cpp/classes/java_class.hpp>
#include <godot_cpp/classes/java_class_wrapper.hpp>
#include <godot_cpp/classes/java_object.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <dlfcn.h>
#include <jni.h>

#include <string>

namespace {

JavaVM *g_vm = nullptr;

// Same-library detection so a stray System.load of a *copy* (different
// soinfo) cannot fool us into thinking we got a VM for this image.
int g_anchor = 0;

struct LocalFrame {
	JNIEnv *env;
	explicit LocalFrame(JNIEnv *e) :
			env(e) { env->PushLocalFrame(256); }
	~LocalFrame() { env->PopLocalFrame(nullptr); }
};

bool clear_exception(JNIEnv *env, const char *what, godot::String *r_error) {
	if (!env->ExceptionCheck()) {
		return false;
	}
	jthrowable t = env->ExceptionOccurred();
	env->ExceptionClear();
	godot::String msg = godot::String("Java exception in ") + what;
	if (t) {
		jclass cls = env->GetObjectClass(t);
		jmethodID toString = env->GetMethodID(cls, "toString", "()Ljava/lang/String;");
		if (toString) {
			jstring s = (jstring)env->CallObjectMethod(t, toString);
			if (s && !env->ExceptionCheck()) {
				const char *c = env->GetStringUTFChars(s, nullptr);
				msg += godot::String(": ") + c;
				env->ReleaseStringUTFChars(s, c);
			}
			env->ExceptionClear();
		}
	}
	if (r_error) {
		*r_error = msg;
	}
	return true;
}

JNIEnv *get_env() {
	if (!g_vm) {
		return nullptr;
	}
	JNIEnv *env = nullptr;
	if (g_vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) == JNI_OK) {
		return env;
	}
	if (g_vm->AttachCurrentThread(&env, nullptr) == JNI_OK) {
		return env;
	}
	return nullptr;
}

} // namespace

extern "C" __attribute__((visibility("default"))) jint JNI_OnLoad(JavaVM *vm, void *) {
	g_vm = vm;
	return JNI_VERSION_1_6;
}

namespace eagler {

bool AndroidJni::ensure_vm(godot::String *r_error) {
	if (g_vm) {
		return true;
	}
	// 1) Some runtimes export JNI_GetCreatedJavaVMs to the app namespace.
	using GetVMs = jint (*)(JavaVM **, jsize, jsize *);
	if (auto fn = reinterpret_cast<GetVMs>(dlsym(RTLD_DEFAULT, "JNI_GetCreatedJavaVMs"))) {
		JavaVM *vm = nullptr;
		jsize n = 0;
		if (fn(&vm, 1, &n) == JNI_OK && n > 0 && vm) {
			g_vm = vm;
			return true;
		}
	}
	// 2) Ask ART to "load" this library: it is already mapped, so dlopen
	//    returns the same image and ART invokes our JNI_OnLoad.
	Dl_info info{};
	if (!dladdr(reinterpret_cast<void *>(&g_anchor), &info) || !info.dli_fname) {
		if (r_error) {
			*r_error = "dladdr failed for own library";
		}
		return false;
	}
	godot::JavaClassWrapper *jcw = godot::JavaClassWrapper::get_singleton();
	godot::Ref<godot::JavaClass> System = jcw->wrap("java.lang.System");
	if (System.is_null()) {
		if (r_error) {
			*r_error = "cannot wrap java.lang.System";
		}
		return false;
	}
	System->call("load", godot::String(info.dli_fname));
	godot::Ref<godot::JavaObject> ex = jcw->get_exception();
	if (ex.is_valid()) {
		if (r_error) {
			*r_error = godot::String("System.load(") + info.dli_fname + ") threw " + godot::String(ex->call("toString"));
		}
		return false;
	}
	if (!g_vm && r_error) {
		*r_error = godot::String("System.load(") + info.dli_fname + ") succeeded but JNI_OnLoad was not invoked";
	}
	return g_vm != nullptr;
}

int AndroidJni::configure_webview(const godot::String &p_property_key, const WebSettings &s, godot::String *r_error) {
	if (!ensure_vm(r_error)) {
		return 0;
	}
	JNIEnv *env = get_env();
	if (!env) {
		if (r_error) {
			*r_error = "no JNIEnv";
		}
		return 0;
	}
	LocalFrame frame(env);

	// System.getProperties().get(key) -> WebView
	jclass System = env->FindClass("java/lang/System");
	jmethodID getProperties = System ? env->GetStaticMethodID(System, "getProperties", "()Ljava/util/Properties;") : nullptr;
	jobject props = getProperties ? env->CallStaticObjectMethod(System, getProperties) : nullptr;
	jclass Hashtable = env->FindClass("java/util/Hashtable");
	jmethodID get = Hashtable ? env->GetMethodID(Hashtable, "get", "(Ljava/lang/Object;)Ljava/lang/Object;") : nullptr;
	jmethodID remove = Hashtable ? env->GetMethodID(Hashtable, "remove", "(Ljava/lang/Object;)Ljava/lang/Object;") : nullptr;
	if (clear_exception(env, "System.getProperties", r_error) || !props || !get) {
		if (r_error && r_error->is_empty()) {
			*r_error = "System.getProperties unavailable";
		}
		return 0;
	}
	// The wrapper can only pass JavaObjects (not Strings) to Object-typed
	// parameters, so the WebView was stored as put(webView, webView). Scan
	// the values for the android.webkit.WebView instance and unlink it.
	(void)get;
	(void)p_property_key;
	jclass WebView = env->FindClass("android/webkit/WebView");
	jmethodID values = Hashtable ? env->GetMethodID(Hashtable, "values", "()Ljava/util/Collection;") : nullptr;
	jobject coll = values ? env->CallObjectMethod(props, values) : nullptr;
	jclass Collection = env->FindClass("java/util/Collection");
	jmethodID toArray = Collection ? env->GetMethodID(Collection, "toArray", "()[Ljava/lang/Object;") : nullptr;
	jobjectArray arr = (coll && toArray) ? (jobjectArray)env->CallObjectMethod(coll, toArray) : nullptr;
	if (clear_exception(env, "Properties.values", r_error) || !arr || !WebView) {
		if (r_error && r_error->is_empty()) {
			*r_error = "cannot enumerate System properties";
		}
		return 0;
	}
	jobject webview = nullptr;
	const jsize n = env->GetArrayLength(arr);
	for (jsize i = 0; i < n && !webview; ++i) {
		jobject o = env->GetObjectArrayElement(arr, i);
		if (o && env->IsInstanceOf(o, WebView)) {
			webview = o;
		} else if (o) {
			env->DeleteLocalRef(o);
		}
	}
	if (!webview) {
		if (r_error) {
			*r_error = "no android.webkit.WebView among " + godot::String::num_int64(n) + " System property values";
		}
		return 0;
	}
	if (remove) {
		env->CallObjectMethod(props, remove, webview);
		env->ExceptionClear();
	}

	jmethodID getSettings = WebView ? env->GetMethodID(WebView, "getSettings", "()Landroid/webkit/WebSettings;") : nullptr;
	jobject settings = getSettings ? env->CallObjectMethod(webview, getSettings) : nullptr;
	if (clear_exception(env, "WebView.getSettings", r_error) || !settings) {
		if (r_error && r_error->is_empty()) {
			*r_error = "WebView.getSettings returned null";
		}
		return 0;
	}
	jclass WS = env->FindClass("android/webkit/WebSettings");
	if (!WS) {
		env->ExceptionClear();
		if (r_error) {
			*r_error = "android.webkit.WebSettings not found";
		}
		return 0;
	}

	int applied = 0;
	godot::String skipped;
	auto set_bool = [&](const char *name, bool v) {
		jmethodID m = env->GetMethodID(WS, name, "(Z)V");
		if (!m) {
			env->ExceptionClear();
			skipped += godot::String(name) + " ";
			return;
		}
		env->CallVoidMethod(settings, m, static_cast<jboolean>(v));
		if (env->ExceptionCheck()) {
			env->ExceptionClear();
			skipped += godot::String(name) + "! ";
			return;
		}
		applied++;
	};
	auto set_int = [&](const char *name, int v) {
		jmethodID m = env->GetMethodID(WS, name, "(I)V");
		if (!m) {
			env->ExceptionClear();
			skipped += godot::String(name) + " ";
			return;
		}
		env->CallVoidMethod(settings, m, static_cast<jint>(v));
		if (env->ExceptionCheck()) {
			env->ExceptionClear();
			skipped += godot::String(name) + "! ";
			return;
		}
		applied++;
	};

	set_bool("setJavaScriptEnabled", s.javascript);
	set_bool("setDomStorageEnabled", s.dom_storage);
	set_bool("setDatabaseEnabled", s.database);
	set_bool("setAllowFileAccess", s.file_access);
	set_bool("setAllowContentAccess", s.content_access);
	set_bool("setMediaPlaybackRequiresUserGesture", s.media_requires_gesture);
	set_bool("setJavaScriptCanOpenWindowsAutomatically", s.js_open_windows);
	set_bool("setSupportZoom", s.zoom);
	set_bool("setBuiltInZoomControls", s.zoom);
	set_bool("setDisplayZoomControls", s.zoom);
	set_bool("setUseWideViewPort", s.wide_viewport);
	set_bool("setLoadWithOverviewMode", s.overview_mode);
	set_int("setMixedContentMode", s.mixed_content_mode);
	set_int("setCacheMode", s.cache_mode);
	set_bool("setBlockNetworkLoads", false);
	set_bool("setGeolocationEnabled", s.geolocation);
	set_bool("setSafeBrowsingEnabled", s.safe_browsing);
	set_bool("setOffscreenPreRaster", s.offscreen_preraster);
	// WebSettings.setRenderPriority(RenderPriority) - enum parameter.
	{
		jclass RP = env->FindClass("android/webkit/WebSettings$RenderPriority");
		if (RP) {
			jfieldID f = env->GetStaticFieldID(RP, s.render_priority == 1 ? "HIGH" : "NORMAL", "Landroid/webkit/WebSettings$RenderPriority;");
			jmethodID m = env->GetMethodID(WS, "setRenderPriority", "(Landroid/webkit/WebSettings$RenderPriority;)V");
			if (f && m) {
				jobject v = env->GetStaticObjectField(RP, f);
				env->CallVoidMethod(settings, m, v);
				if (env->ExceptionCheck()) {
					env->ExceptionClear();
				} else {
					++applied;
				}
			} else {
				env->ExceptionClear();
			}
		} else {
			env->ExceptionClear();
		}
	}

	// Read back the one that matters so the log proves it.
	jmethodID getJs = env->GetMethodID(WS, "getJavaScriptEnabled", "()Z");
	bool js_on = getJs ? env->CallBooleanMethod(settings, getJs) : false;
	env->ExceptionClear();
	godot::UtilityFunctions::print("[EaglerHost] WebSettings via JNI: ", applied, " setters applied, javaScriptEnabled=", js_on,
			skipped.is_empty() ? godot::String() : godot::String(" (skipped: ") + skipped + ")");
	if (!js_on && r_error) {
		*r_error = "setJavaScriptEnabled did not take effect";
		return 0;
	}
	return applied;
}

} // namespace eagler

#else // !__ANDROID__

namespace eagler {
bool AndroidJni::ensure_vm(godot::String *r_error) {
	if (r_error) {
		*r_error = "not Android";
	}
	return false;
}
int AndroidJni::configure_webview(const godot::String &, const WebSettings &, godot::String *r_error) {
	if (r_error) {
		*r_error = "not Android";
	}
	return 0;
}
} // namespace eagler

#endif
