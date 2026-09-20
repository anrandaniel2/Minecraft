// SPDX-License-Identifier: MIT
//
// EaglerHost - Godot node that hosts the EaglerCraft HTML build on Android.
//
// Pipeline:
//   1. Extract res://web/* (packed in the PCK) to user://web/ on a worker
//      thread. The extraction is skipped if the on-disk copy is up to date.
//   2. Start LocalHttpServer (multi-threaded, loopback only).
//   3. On the Android UI thread, create an android.webkit.WebView through
//      JavaClassWrapper, switch it to LAYER_TYPE_HARDWARE, enable WebGL /
//      JS / DOM storage, and attach it on top of Godot's Vulkan surface.
//   4. Forward lifecycle events (pause/resume/back) to the WebView.
//
// Godot itself keeps running its Vulkan "Forward Mobile" renderer underneath
// with a separate render thread (see project.godot), and the Chromium WebView
// composites through its own GPU process. The WebGL context used by the game
// is hardware accelerated via ANGLE-on-Vulkan / GLES on the device GPU.

#pragma once

#include <godot_cpp/classes/java_class.hpp>
#include <godot_cpp/classes/java_object.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_string_array.hpp>
#include <godot_cpp/variant/string.hpp>

#include <atomic>
#include <memory>
#include <string>
#include <thread>

#include "local_http_server.h"

namespace godot {

class EaglerHost : public Node {
	GDCLASS(EaglerHost, Node)

public:
	enum State {
		STATE_IDLE,
		STATE_EXTRACTING,
		STATE_SERVING,
		STATE_WEBVIEW_READY,
		STATE_ERROR,
	};

	EaglerHost();
	~EaglerHost() override;

	// --- Properties -------------------------------------------------------
	void set_html_resource_path(const String &p_path);
	String get_html_resource_path() const;

	void set_extra_web_files(const PackedStringArray &p_files);
	PackedStringArray get_extra_web_files() const;

	void set_use_hardware_layer(bool p_enabled);
	bool get_use_hardware_layer() const;

	void set_immersive(bool p_enabled);
	void set_safe_mode(bool p_enabled);
	bool get_safe_mode() const;
	// "auto" (WebGPU when navigator.gpu exists, else WebGL2), "webgpu", "webgl2".
	void set_graphics_backend(const String &p_backend);
	String get_graphics_backend() const;
	void set_sustained_performance(bool p_enabled);
	bool get_sustained_performance() const;
	void set_stop_host_render_loop(bool p_enabled);
	bool get_stop_host_render_loop() const;
	bool get_immersive() const;

	void set_cross_origin_isolation(bool p_enabled);
	bool get_cross_origin_isolation() const;

	void set_worker_threads(int p_threads);
	int get_worker_threads() const;

	void set_host_fps_when_hidden(int p_fps);
	int get_host_fps_when_hidden() const;

	void set_native_unpack(bool p_enabled);
	bool get_native_unpack() const;
	void set_enable_game_workers(bool p_enabled);
	bool get_enable_game_workers() const;
	bool is_unpacked() const;

	void set_offline_only(bool p_enabled);
	bool get_offline_only() const;

	// --- Runtime API -------------------------------------------------------
	String get_base_url() const;
	int get_state() const;
	String get_last_error() const;
	int get_server_port() const;
	int get_server_worker_count() const;
	int64_t get_requests_served() const;
	void reload();
	void evaluate_javascript(const String &p_script);
	void show_banner(const String &p_message, const Dictionary &p_buttons);
	void hide_banner();

	void _ready() override;
	void _process(double p_delta) override;
	void _exit_tree() override;
	void _notification(int p_what);

protected:
	static void _bind_methods();

private:
	// Called (via Callable) on the Android UI thread.
	void _ui_create_webview();
	void _ui_destroy_webview();
	void _ui_load_url(const String &p_url);
	void _ui_eval_js(const String &p_script);
	void _ui_pause();
	void _ui_resume();
	void _ui_back();

	// Helpers.
	void _start_extraction();
	void _extraction_thread_main();
	bool _extract_file(const String &p_res_path, const std::string &p_dest_dir, std::string *p_error);
	bool _start_server();
	void _request_webview();
	void _run_on_ui_thread(const Callable &p_callable);
	void _set_error(const String &p_msg);
	void _apply_immersive_mode();
	void _ui_reapply_fullscreen();
	int _android_sdk_int();
	void _throttle_host_renderer();
	void _tick_offline_guard(double p_delta);
	void _tick_boot_watchdog(double p_delta);
	String _page_url() const;
	void _on_page_command(const String &p_command);
	void _on_update_available(const String &p_version, const String &p_notes);
	void _on_update_progress(int64_t p_bytes, int64_t p_total);
	void _on_update_downloaded(const String &p_apk_path);
	void _on_update_error(const String &p_message);
	void _connect_updater();
	void _log(const String &p_msg) const;

	// Config.
	String html_resource_path_ = "res://web/eaglercraft.html";
	PackedStringArray extra_web_files_;
	bool use_hardware_layer_ = true;
	bool immersive_ = true;
	bool cross_origin_isolation_ = false;
	int worker_threads_ = 0;
	bool offline_only_ = true;
	bool native_unpack_ = true;
	int host_fps_when_hidden_ = 10;
	bool enable_game_workers_ = true;
	std::atomic<bool> unpacked_{ false };

	// State.
	std::atomic<int> state_{ STATE_IDLE };
	std::atomic<bool> extraction_done_{ false };
	std::atomic<bool> extraction_ok_{ false };
	std::string extraction_error_;
	std::string web_root_;
	String last_error_;
	std::thread extraction_thread_;

	std::unique_ptr<eagler::LocalHttpServer> server_;

	// Android objects (only valid on Android).
	bool is_android_ = false;
	Ref<JavaObject> activity_;
	Ref<JavaObject> webview_;
	Object *android_runtime_ = nullptr;
	bool webview_requested_ = false;
	bool paused_ = false;
	int guard_injections_ = 0;
	int sdk_int_ = -1;
	bool fullscreen_dirty_ = false;
	double fullscreen_timer_ = 0.0;
	double guard_timer_ = 0.0;
	std::atomic<bool> page_ready_{ false };
	bool safe_mode_ = false; // load the page with ?singlethread (workers off)
	String graphics_backend_ = "auto";
	bool sustained_performance_ = true;
	bool stop_host_render_loop_ = true;
	int watchdog_dumps_ = 0;
	double watchdog_timer_ = 0.0;
};

} // namespace godot

VARIANT_ENUM_CAST(godot::EaglerHost::State);
