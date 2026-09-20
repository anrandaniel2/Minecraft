// SPDX-License-Identifier: MIT
//
// Minimal raw-JNI escape hatch for cases Godot's JavaClassWrapper cannot
// handle: objects whose *runtime* class lives outside the application
// class loader (e.g. android.webkit.WebSettings, implemented by the WebView
// provider APK as com.android.webview.chromium.ContentSettingsAdapter).
// JavaClassWrapper resolves returned objects by runtime class through the
// app loader, fails, and yields null. Plain JNI against the framework base
// class works because dispatch is virtual.
//
// A GDExtension is dlopen()ed by Godot, so JNI_OnLoad is never invoked by
// ART. ensure_vm() asks Java to System.load() this very library, which makes
// ART call our JNI_OnLoad and hand us the JavaVM.

#pragma once

#include <godot_cpp/variant/string.hpp>

namespace eagler {

class AndroidJni {
public:
	struct WebSettings {
		bool javascript = true;
		bool dom_storage = true;
		bool database = true;
		bool file_access = false;
		bool content_access = false;
		bool media_requires_gesture = false;
		bool js_open_windows = false;
		bool zoom = false;
		bool wide_viewport = true;
		bool overview_mode = true;
		int mixed_content_mode = 2; // MIXED_CONTENT_COMPATIBILITY_MODE
		int cache_mode = -1; // LOAD_DEFAULT
		bool geolocation = false;
		bool safe_browsing = false;
		bool offscreen_preraster = true;
	};

	// True on Android when a JavaVM* is available (obtained lazily).
	static bool ensure_vm(godot::String *r_error = nullptr);

	// Apply WebSettings to the android.webkit.WebView previously published
	// under System.getProperties().put(p_property_key, webView).
	// Must run on the UI thread (any attached thread works for JNI, but the
	// WebView API itself is thread-affine). Returns the number of setters
	// successfully invoked (0 on failure); r_error explains failures.
	static int configure_webview(const godot::String &p_property_key, const WebSettings &p_settings, godot::String *r_error = nullptr);
};

} // namespace eagler
