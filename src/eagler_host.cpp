// SPDX-License-Identifier: MIT

#include "eagler_host.h"

#include "bundle_unpacker.h"

#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/classes/display_server.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/java_class_wrapper.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/classes/rendering_server.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/callable_method_pointer.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

#include <sys/stat.h>

#include <functional>

namespace godot {

namespace {

// Bumping this forces a re-extraction of the web bundle on next launch.
constexpr const char *kBundleStampFile = ".eagler_bundle_stamp";

// android.view.View#SYSTEM_UI_FLAG_* combination for sticky immersive mode.
constexpr int kImmersiveFlags = 0x00000100 /*LAYOUT_STABLE*/
		| 0x00000200 /*LAYOUT_HIDE_NAVIGATION*/
		| 0x00000400 /*LAYOUT_FULLSCREEN*/
		| 0x00000002 /*HIDE_NAVIGATION*/
		| 0x00000004 /*FULLSCREEN*/
		| 0x00001000 /*IMMERSIVE_STICKY*/;

// android.view.View#LAYER_TYPE_HARDWARE
constexpr int kLayerTypeHardware = 2;
// android.view.ViewGroup.LayoutParams#MATCH_PARENT
constexpr int kMatchParent = -1;
// android.webkit.WebSettings#MIXED_CONTENT_COMPATIBILITY_MODE
constexpr int kMixedContentCompat = 2;
// android.webkit.WebSettings#LOAD_DEFAULT
constexpr int kCacheLoadDefault = -1;
// android.webkit.WebSettings#LOAD_CACHE_ELSE_NETWORK (never wait on the network).
constexpr int kCacheLoadCacheElseNetwork = 1;

// Injected into the page when offline_only is set. Rejects every request whose
// origin is not the loopback server so the game can never reach the network.
constexpr const char *kOfflineGuardJs = R"JS(
(function(){
  if (window.fetch && window.fetch.__eaglerGuarded) return;
  var ok = function(u){ try { u = new URL(u, location.href); } catch(e){ return true; }
    return u.protocol === 'data:' || u.protocol === 'blob:' || u.protocol === 'eagler-inline-payload:' ||
           u.origin === location.origin; };
  var install = function(){
    var f = window.fetch;
    window.fetch = function(i, o){ var u = (i && i.url) || i;
      if (!ok(u)) return Promise.reject(new TypeError('offline: blocked ' + u)); return f.call(this, i, o); };
    window.fetch.__eaglerGuarded = true;
    if (XMLHttpRequest.prototype.open.__eaglerGuarded) return;
    var open = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(m, u){ if (!ok(u)) throw new TypeError('offline: blocked ' + u);
      return open.apply(this, arguments); };
    XMLHttpRequest.prototype.open.__eaglerGuarded = true;
    var WS = window.WebSocket;
    window.WebSocket = function(u, p){ if (!ok(u)) throw new TypeError('offline: blocked ' + u);
      return p === undefined ? new WS(u) : new WS(u, p); };
    window.WebSocket.prototype = WS.prototype;
    Object.defineProperty(navigator, 'onLine', { get: function(){ return false; }, configurable: true });
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', install); else install();
})();
)JS";

// In-page update banner (injected via evaluateJavascript). Pure DOM, no
// dependency on the game. Buttons call back into the host through the
// loopback server's /__host/ endpoint.
constexpr const char *kUpdateBannerJs = R"JS(
(function(){
  var id='__eagler_update_banner';
  var old=document.getElementById(id); if(old) old.remove();
  var d=document.createElement('div'); d.id=id;
  d.style.cssText='position:fixed;left:0;right:0;top:0;z-index:2147483647;background:rgba(20,24,28,.94);color:#eee;'+
    'font:14px/1.4 system-ui,sans-serif;padding:10px 14px;display:flex;gap:10px;align-items:center;'+
    'box-shadow:0 2px 12px rgba(0,0,0,.6);border-bottom:1px solid #3a4;';
  var t=document.createElement('div'); t.style.flex='1'; t.textContent=__MSG__; d.appendChild(t);
  var p=document.createElement('div'); p.id=id+'_p'; p.style.cssText='min-width:52px;text-align:right;color:#9d9'; d.appendChild(p);
  function btn(label,cmd,primary){var b=document.createElement('button');b.textContent=label;
    b.style.cssText='padding:8px 14px;border:0;border-radius:6px;font-weight:600;'+(primary?'background:#3a4;color:#fff':'background:#334;color:#ccc');
    b.onclick=function(){fetch('/__host/'+cmd).catch(function(){});if(cmd==='dismiss')d.remove();};d.appendChild(b);}
  __BUTTONS__
  document.body.appendChild(d);
})();
)JS";
constexpr const char *kUpdateProgressJs = R"JS(
(function(){var p=document.getElementById('__eagler_update_banner_p');if(p)p.textContent=__PCT__;})();
)JS";

bool make_dirs(const std::string &path) {
	std::string cur;
	for (size_t i = 0; i < path.size(); ++i) {
		cur.push_back(path[i]);
		if (path[i] == '/' && cur.size() > 1) {
			::mkdir(cur.c_str(), 0755);
		}
	}
	::mkdir(path.c_str(), 0755);
	struct stat st{};
	return ::stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

} // namespace

EaglerHost::EaglerHost() {
	is_android_ = OS::get_singleton() && OS::get_singleton()->get_name() == "Android";
}

EaglerHost::~EaglerHost() {
	if (extraction_thread_.joinable()) {
		extraction_thread_.join();
	}
	if (server_) {
		server_->stop();
	}
}

// ---------------------------------------------------------------------------
// Bindings
// ---------------------------------------------------------------------------

void EaglerHost::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_html_resource_path", "path"), &EaglerHost::set_html_resource_path);
	ClassDB::bind_method(D_METHOD("get_html_resource_path"), &EaglerHost::get_html_resource_path);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "html_resource_path", PROPERTY_HINT_FILE, "*.html"), "set_html_resource_path", "get_html_resource_path");

	ClassDB::bind_method(D_METHOD("set_extra_web_files", "files"), &EaglerHost::set_extra_web_files);
	ClassDB::bind_method(D_METHOD("get_extra_web_files"), &EaglerHost::get_extra_web_files);
	ADD_PROPERTY(PropertyInfo(Variant::PACKED_STRING_ARRAY, "extra_web_files"), "set_extra_web_files", "get_extra_web_files");

	ClassDB::bind_method(D_METHOD("set_use_hardware_layer", "enabled"), &EaglerHost::set_use_hardware_layer);
	ClassDB::bind_method(D_METHOD("get_use_hardware_layer"), &EaglerHost::get_use_hardware_layer);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "use_hardware_layer"), "set_use_hardware_layer", "get_use_hardware_layer");

	ClassDB::bind_method(D_METHOD("set_immersive", "enabled"), &EaglerHost::set_immersive);
	ClassDB::bind_method(D_METHOD("get_immersive"), &EaglerHost::get_immersive);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "immersive"), "set_immersive", "get_immersive");

	ClassDB::bind_method(D_METHOD("set_cross_origin_isolation", "enabled"), &EaglerHost::set_cross_origin_isolation);
	ClassDB::bind_method(D_METHOD("get_cross_origin_isolation"), &EaglerHost::get_cross_origin_isolation);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "cross_origin_isolation"), "set_cross_origin_isolation", "get_cross_origin_isolation");

	ClassDB::bind_method(D_METHOD("set_worker_threads", "threads"), &EaglerHost::set_worker_threads);
	ClassDB::bind_method(D_METHOD("get_worker_threads"), &EaglerHost::get_worker_threads);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "worker_threads", PROPERTY_HINT_RANGE, "0,16,1"), "set_worker_threads", "get_worker_threads");

	ClassDB::bind_method(D_METHOD("set_native_unpack", "enabled"), &EaglerHost::set_native_unpack);
	ClassDB::bind_method(D_METHOD("get_native_unpack"), &EaglerHost::get_native_unpack);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "native_unpack"), "set_native_unpack", "get_native_unpack");
	ClassDB::bind_method(D_METHOD("set_enable_game_workers", "enabled"), &EaglerHost::set_enable_game_workers);
	ClassDB::bind_method(D_METHOD("get_enable_game_workers"), &EaglerHost::get_enable_game_workers);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "enable_game_workers"), "set_enable_game_workers", "get_enable_game_workers");
	ClassDB::bind_method(D_METHOD("is_unpacked"), &EaglerHost::is_unpacked);

	ClassDB::bind_method(D_METHOD("set_offline_only", "enabled"), &EaglerHost::set_offline_only);
	ClassDB::bind_method(D_METHOD("get_offline_only"), &EaglerHost::get_offline_only);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "offline_only"), "set_offline_only", "get_offline_only");

	ClassDB::bind_method(D_METHOD("get_base_url"), &EaglerHost::get_base_url);
	ClassDB::bind_method(D_METHOD("get_state"), &EaglerHost::get_state);
	ClassDB::bind_method(D_METHOD("get_last_error"), &EaglerHost::get_last_error);
	ClassDB::bind_method(D_METHOD("get_server_port"), &EaglerHost::get_server_port);
	ClassDB::bind_method(D_METHOD("get_server_worker_count"), &EaglerHost::get_server_worker_count);
	ClassDB::bind_method(D_METHOD("get_requests_served"), &EaglerHost::get_requests_served);
	ClassDB::bind_method(D_METHOD("reload"), &EaglerHost::reload);
	ClassDB::bind_method(D_METHOD("evaluate_javascript", "script"), &EaglerHost::evaluate_javascript);

	// UI-thread trampolines (must be bound so they can be wrapped in a Callable).
	ClassDB::bind_method(D_METHOD("_ui_create_webview"), &EaglerHost::_ui_create_webview);
	ClassDB::bind_method(D_METHOD("_ui_destroy_webview"), &EaglerHost::_ui_destroy_webview);
	ClassDB::bind_method(D_METHOD("_ui_load_url", "url"), &EaglerHost::_ui_load_url);
	ClassDB::bind_method(D_METHOD("_ui_eval_js", "script"), &EaglerHost::_ui_eval_js);
	ClassDB::bind_method(D_METHOD("_ui_pause"), &EaglerHost::_ui_pause);
	ClassDB::bind_method(D_METHOD("_ui_resume"), &EaglerHost::_ui_resume);
	ClassDB::bind_method(D_METHOD("_ui_back"), &EaglerHost::_ui_back);
	ClassDB::bind_method(D_METHOD("_throttle_host_renderer"), &EaglerHost::_throttle_host_renderer);
	ClassDB::bind_method(D_METHOD("_ui_reapply_fullscreen"), &EaglerHost::_ui_reapply_fullscreen);
	ClassDB::bind_method(D_METHOD("_on_page_command", "command"), &EaglerHost::_on_page_command);
	ClassDB::bind_method(D_METHOD("_connect_updater"), &EaglerHost::_connect_updater);
	ClassDB::bind_method(D_METHOD("set_safe_mode", "enabled"), &EaglerHost::set_safe_mode);
	ClassDB::bind_method(D_METHOD("get_safe_mode"), &EaglerHost::get_safe_mode);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "safe_mode"), "set_safe_mode", "get_safe_mode");
	ClassDB::bind_method(D_METHOD("_on_update_available", "version", "notes"), &EaglerHost::_on_update_available);
	ClassDB::bind_method(D_METHOD("_on_update_progress", "bytes", "total"), &EaglerHost::_on_update_progress);
	ClassDB::bind_method(D_METHOD("_on_update_downloaded", "apk_path"), &EaglerHost::_on_update_downloaded);
	ClassDB::bind_method(D_METHOD("_on_update_error", "message"), &EaglerHost::_on_update_error);
	ClassDB::bind_method(D_METHOD("show_banner", "message", "buttons"), &EaglerHost::show_banner);
	ClassDB::bind_method(D_METHOD("hide_banner"), &EaglerHost::hide_banner);

	ADD_SIGNAL(MethodInfo("page_command", PropertyInfo(Variant::STRING, "command")));

	ClassDB::bind_method(D_METHOD("set_host_fps_when_hidden", "fps"), &EaglerHost::set_host_fps_when_hidden);
	ClassDB::bind_method(D_METHOD("get_host_fps_when_hidden"), &EaglerHost::get_host_fps_when_hidden);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "host_fps_when_hidden", PROPERTY_HINT_RANGE, "1,120,1"), "set_host_fps_when_hidden", "get_host_fps_when_hidden");

	ADD_SIGNAL(MethodInfo("server_started", PropertyInfo(Variant::STRING, "base_url")));
	ADD_SIGNAL(MethodInfo("webview_ready"));
	ADD_SIGNAL(MethodInfo("host_error", PropertyInfo(Variant::STRING, "message")));

	BIND_ENUM_CONSTANT(STATE_IDLE);
	BIND_ENUM_CONSTANT(STATE_EXTRACTING);
	BIND_ENUM_CONSTANT(STATE_SERVING);
	BIND_ENUM_CONSTANT(STATE_WEBVIEW_READY);
	BIND_ENUM_CONSTANT(STATE_ERROR);
}

// ---------------------------------------------------------------------------
// Properties
// ---------------------------------------------------------------------------

void EaglerHost::set_html_resource_path(const String &p_path) { html_resource_path_ = p_path; }
String EaglerHost::get_html_resource_path() const { return html_resource_path_; }
void EaglerHost::set_extra_web_files(const PackedStringArray &p_files) { extra_web_files_ = p_files; }
PackedStringArray EaglerHost::get_extra_web_files() const { return extra_web_files_; }
void EaglerHost::set_use_hardware_layer(bool p_enabled) { use_hardware_layer_ = p_enabled; }
bool EaglerHost::get_use_hardware_layer() const { return use_hardware_layer_; }
void EaglerHost::set_immersive(bool p_enabled) { immersive_ = p_enabled; }
void EaglerHost::set_safe_mode(bool p_enabled) { safe_mode_ = p_enabled; }
bool EaglerHost::get_safe_mode() const { return safe_mode_; }
bool EaglerHost::get_immersive() const { return immersive_; }
void EaglerHost::set_cross_origin_isolation(bool p_enabled) { cross_origin_isolation_ = p_enabled; }
bool EaglerHost::get_cross_origin_isolation() const { return cross_origin_isolation_; }
void EaglerHost::set_worker_threads(int p_threads) { worker_threads_ = p_threads; }
void EaglerHost::set_host_fps_when_hidden(int p_fps) { host_fps_when_hidden_ = p_fps; }
int EaglerHost::get_host_fps_when_hidden() const { return host_fps_when_hidden_; }
void EaglerHost::set_native_unpack(bool p_enabled) { native_unpack_ = p_enabled; }
bool EaglerHost::get_native_unpack() const { return native_unpack_; }
void EaglerHost::set_enable_game_workers(bool p_enabled) { enable_game_workers_ = p_enabled; }
bool EaglerHost::get_enable_game_workers() const { return enable_game_workers_; }
bool EaglerHost::is_unpacked() const { return unpacked_; }
void EaglerHost::set_offline_only(bool p_enabled) { offline_only_ = p_enabled; }
bool EaglerHost::get_offline_only() const { return offline_only_; }
int EaglerHost::get_worker_threads() const { return worker_threads_; }

String EaglerHost::get_base_url() const {
	return server_ && server_->is_running() ? String(server_->base_url().c_str()) : String();
}
int EaglerHost::get_state() const { return state_.load(); }
String EaglerHost::get_last_error() const { return last_error_; }
int EaglerHost::get_server_port() const { return server_ ? server_->port() : 0; }
int EaglerHost::get_server_worker_count() const { return server_ ? static_cast<int>(server_->worker_count()) : 0; }
int64_t EaglerHost::get_requests_served() const { return server_ ? static_cast<int64_t>(server_->requests_served()) : 0; }

// ---------------------------------------------------------------------------
// Lifecycle
// ---------------------------------------------------------------------------

void EaglerHost::_log(const String &p_msg) const {
	UtilityFunctions::print("[EaglerHost] ", p_msg);
}

void EaglerHost::_set_error(const String &p_msg) {
	last_error_ = p_msg;
	state_.store(STATE_ERROR);
	UtilityFunctions::push_error("[EaglerHost] ", p_msg);
	// May be called from the Android UI thread: defer to the main thread.
	call_deferred("emit_signal", "host_error", p_msg);
}

void EaglerHost::_ready() {
	if (Engine::get_singleton()->is_editor_hint()) {
		return;
	}
	_log(String("Renderer: ") + RenderingServer::get_singleton()->get_current_rendering_driver_name() +
			" / " + RenderingServer::get_singleton()->get_current_rendering_method() +
			", CPU threads: " + String::num_int64(OS::get_singleton()->get_processor_count()));

	if (is_android_) {
		if (Engine::get_singleton()->has_singleton("AndroidRuntime")) {
			android_runtime_ = Engine::get_singleton()->get_singleton("AndroidRuntime");
			activity_ = android_runtime_->call("getActivity");
		}
		if (activity_.is_null()) {
			_set_error("AndroidRuntime singleton / Activity unavailable (requires Godot 4.4+ Android template).");
			return;
		}
	} else {
		_log("Not running on Android: the WebView will not be created, but the bundle is still extracted and served.");
	}

	if (!FileAccess::file_exists(html_resource_path_)) {
		UtilityFunctions::push_warning("[EaglerHost] ", html_resource_path_,
				" not found in the project; serving the placeholder page instead. See web/README.md.");
		html_resource_path_ = html_resource_path_.get_base_dir().path_join("index_placeholder.html");
	}

	set_process(true);
	if (is_android_) {
		_run_on_ui_thread(Callable(this, "_ui_reapply_fullscreen"));
	}
	call_deferred("_connect_updater"); // children are ready after us
	_start_extraction();
}

void EaglerHost::_tick_offline_guard(double p_delta) {
	if (!offline_only_ || !is_android_ || webview_.is_null() || state_.load() != STATE_WEBVIEW_READY) {
		return;
	}
	// The guard script is idempotent and wraps whatever window.fetch is
	// current, so re-running it after the page's own shim is installed keeps
	// both layers intact. Re-inject a few times during the first seconds and
	// then once more per reload.
	guard_timer_ += p_delta;
	if (guard_injections_ < 6 && guard_timer_ >= 1.0) {
		guard_timer_ = 0.0;
		guard_injections_++;
		_run_on_ui_thread(Callable(this, "_ui_eval_js").bind(String(kOfflineGuardJs)));
	}
}

void EaglerHost::_tick_boot_watchdog(double p_delta) {
	// If the page has not reported "game-ready" after a while, ask it to dump
	// its boot log + crash journal so a stuck splash screen is diagnosable
	// from logcat alone. Repeats a few times, then stops.
	if (!is_android_ || webview_.is_null() || state_.load() != STATE_WEBVIEW_READY || page_ready_.load() || watchdog_dumps_ >= 4) {
		return;
	}
	watchdog_timer_ += p_delta;
	const double due = watchdog_dumps_ == 0 ? 30.0 : 60.0;
	if (watchdog_timer_ >= due) {
		watchdog_timer_ = 0.0;
		watchdog_dumps_++;
		_log("page not ready after " + String::num_int64(watchdog_dumps_ == 1 ? 30 : 30 + 60 * (watchdog_dumps_ - 1)) + " s; requesting boot dump");
		_run_on_ui_thread(Callable(this, "_ui_eval_js").bind(String("window.__eaglerHostDump && window.__eaglerHostDump();")));
		// Second strike (90 s): most likely the mesh/server workers never came
		// up on this WebView. Reload once in the bundle's own single-thread
		// mode (its "?singlethread" switch) before giving up.
		if (watchdog_dumps_ == 2 && !safe_mode_ && enable_game_workers_) {
			safe_mode_ = true;
			UtilityFunctions::push_warning("[EaglerHost] boot stalled; reloading in single-thread safe mode (?singlethread)");
			reload();
		}
	}
}

String EaglerHost::_page_url() const {
	String url = get_base_url();
	if (url.is_empty()) {
		return url;
	}
	if (safe_mode_) {
		url += "?singlethread";
	}
	return url;
}

void EaglerHost::_process(double p_delta) {
	_tick_offline_guard(p_delta);
	_tick_boot_watchdog(p_delta);
	if (immersive_ && is_android_ && webview_.is_valid()) {
		// Cheap periodic re-assert: system UI can reappear after the soft
		// keyboard, dialogs or notification shade; sticky immersive hides it
		// again after a few seconds, this makes it immediate.
		fullscreen_timer_ += p_delta;
		if (fullscreen_timer_ >= 2.0) {
			fullscreen_timer_ = 0.0;
			_run_on_ui_thread(Callable(this, "_ui_reapply_fullscreen"));
		}
	}
	if (state_.load() == STATE_EXTRACTING && extraction_done_.load()) {
		if (extraction_thread_.joinable()) {
			extraction_thread_.join();
		}
		if (!extraction_ok_.load()) {
			_set_error(String("Bundle extraction failed: ") + extraction_error_.c_str());
			return;
		}
		if (!_start_server()) {
			return;
		}
		_request_webview();
	}
}

void EaglerHost::_exit_tree() {
	if (is_android_ && webview_.is_valid()) {
		_run_on_ui_thread(Callable(this, "_ui_destroy_webview"));
	}
	if (server_) {
		server_->stop();
	}
}

void EaglerHost::_notification(int p_what) {
	if (!is_android_ || webview_.is_null()) {
		return;
	}
	switch (p_what) {
		case NOTIFICATION_APPLICATION_PAUSED:
			paused_ = true;
			_run_on_ui_thread(Callable(this, "_ui_pause"));
			break;
		case NOTIFICATION_APPLICATION_RESUMED:
			if (paused_) {
				paused_ = false;
				_run_on_ui_thread(Callable(this, "_ui_resume"));
			}
			break;
		case NOTIFICATION_APPLICATION_FOCUS_IN:
			_run_on_ui_thread(Callable(this, "_ui_reapply_fullscreen"));
			break;
		case NOTIFICATION_WM_GO_BACK_REQUEST:
			_run_on_ui_thread(Callable(this, "_ui_back"));
			break;
		default:
			break;
	}
}

// ---------------------------------------------------------------------------
// Bundle extraction (worker thread)
// ---------------------------------------------------------------------------

void EaglerHost::_start_extraction() {
	state_.store(STATE_EXTRACTING);
	extraction_done_.store(false);
	extraction_ok_.store(false);
	web_root_ = ProjectSettings::get_singleton()->globalize_path("user://web").utf8().get_data();
	extraction_thread_ = std::thread(&EaglerHost::_extraction_thread_main, this);
}

bool EaglerHost::_extract_file(const String &p_res_path, const std::string &p_dest_dir, std::string *p_error) {
	String rel = p_res_path;
	const String prefix = html_resource_path_.get_base_dir();
	if (rel.begins_with(prefix)) {
		rel = rel.substr(prefix.length());
	} else {
		rel = "/" + rel.get_file();
	}
	std::string dest = p_dest_dir + rel.utf8().get_data();
	std::string dest_dir = dest.substr(0, dest.find_last_of('/'));
	if (!make_dirs(dest_dir)) {
		*p_error = "mkdir failed: " + dest_dir;
		return false;
	}

	PackedByteArray data = FileAccess::get_file_as_bytes(p_res_path);
	if (data.is_empty() && FileAccess::get_open_error() != OK) {
		*p_error = std::string("cannot read ") + p_res_path.utf8().get_data();
		return false;
	}
	Ref<FileAccess> out = FileAccess::open(String(dest.c_str()), FileAccess::WRITE);
	if (out.is_null()) {
		*p_error = "cannot write " + dest;
		return false;
	}
	out->store_buffer(data);
	out->close();
	return true;
}

void EaglerHost::_extraction_thread_main() {
	std::string err;
	bool ok = true;

	// Collect files: everything under the HTML's directory, plus explicit extras.
	PackedStringArray files;
	const String base_dir = html_resource_path_.get_base_dir();
	std::function<void(const String &)> walk = [&](const String &dir) {
		Ref<DirAccess> da = DirAccess::open(dir);
		if (da.is_null()) {
			return;
		}
		da->list_dir_begin();
		for (String n = da->get_next(); !n.is_empty(); n = da->get_next()) {
			if (n == "." || n == "..") {
				continue;
			}
			String full = dir.path_join(n);
			if (da->current_is_dir()) {
				walk(full);
			} else if (!n.ends_with(".import") && !n.ends_with(".uid")) {
				// In exported builds Godot may remap some files to ".remap"; strip it.
				if (n.ends_with(".remap")) {
					full = full.substr(0, full.length() - 6);
				}
				files.push_back(full);
			}
		}
		da->list_dir_end();
	};
	walk(base_dir);
	for (int i = 0; i < extra_web_files_.size(); ++i) {
		files.push_back(extra_web_files_[i]);
	}
	if (!files.has(html_resource_path_)) {
		files.push_back(html_resource_path_);
	}

	// Stamp: skip work if the same file list & sizes were extracted before.
	String stamp;
	for (int i = 0; i < files.size(); ++i) {
		Ref<FileAccess> f = FileAccess::open(files[i], FileAccess::READ);
		if (f.is_valid()) {
			stamp += files[i] + ":" + String::num_uint64(f->get_length()) + "\n";
		}
	}
	const std::string stamp_path = web_root_ + "/" + kBundleStampFile;
	String existing;
	{
		Ref<FileAccess> f = FileAccess::open(String(stamp_path.c_str()), FileAccess::READ);
		if (f.is_valid()) {
			existing = f->get_as_text();
		}
	}
	bool need_extract = (existing != stamp);

	if (need_extract) {
		if (!make_dirs(web_root_)) {
			err = "cannot create " + web_root_;
			ok = false;
		}
		for (int i = 0; ok && i < files.size(); ++i) {
			ok = _extract_file(files[i], web_root_, &err);
		}
		if (ok) {
			Ref<FileAccess> f = FileAccess::open(String(stamp_path.c_str()), FileAccess::WRITE);
			if (f.is_valid()) {
				f->store_string(stamp);
			}
		}
	}

	// -- Native unpack of the single-file bundle ---------------------------
	// Converts the 75 MB base64 HTML into classes.wasm / *.epk / slim
	// index.html so the WebView can stream-compile and cache the WASM.
	if (ok && native_unpack_) {
		const std::string src = web_root_ + "/" + html_resource_path_.get_file().utf8().get_data();
		const std::string dst = web_root_ + "/unpacked";
		const std::string unpack_stamp = dst + "/" + kBundleStampFile;
		String existing_unpack;
		{
			Ref<FileAccess> f = FileAccess::open(String(unpack_stamp.c_str()), FileAccess::READ);
			if (f.is_valid()) {
				existing_unpack = f->get_as_text();
			}
		}
		if (eagler::BundleUnpacker::is_single_file_bundle(src)) {
			if (existing_unpack != stamp) {
				eagler::BundleUnpacker::Options o;
				o.html_path = src;
				o.out_dir = dst;
				o.index_name = "index.html";
				o.threads = worker_threads_ > 0 ? static_cast<unsigned>(worker_threads_) : 0;
				o.enable_workers = enable_game_workers_;
				o.log = [this](const std::string &m) { _log(String(m.c_str())); };
				eagler::UnpackStats st;
				std::string uerr;
				if (eagler::BundleUnpacker::unpack(o, &st, &uerr)) {
					Ref<FileAccess> f = FileAccess::open(String(unpack_stamp.c_str()), FileAccess::WRITE);
					if (f.is_valid()) {
						f->store_string(stamp);
					}
					_log(String("native unpack: ") + String::num_int64(static_cast<int64_t>(st.decompressed_bytes / 1048576)) +
							" MiB in " + String::num(st.seconds, 2) + " s on " + String::num_int64(st.threads) + " threads");
					unpacked_ = true;
				} else {
					UtilityFunctions::push_warning("[EaglerHost] native unpack failed (", uerr.c_str(), "); falling back to the single-file page.");
				}
			} else {
				unpacked_ = true;
			}
		}
	}

	extraction_error_ = err;
	extraction_ok_.store(ok);
	extraction_done_.store(true);
}

// ---------------------------------------------------------------------------
// HTTP server
// ---------------------------------------------------------------------------

bool EaglerHost::_start_server() {
	server_ = std::make_unique<eagler::LocalHttpServer>();
	eagler::LocalHttpServer::Config cfg;
	if (unpacked_) {
		cfg.root_dir = web_root_ + "/unpacked";
		cfg.index_file = "index.html";
	} else {
		cfg.root_dir = web_root_;
		cfg.index_file = html_resource_path_.get_file().utf8().get_data();
	}
	// COOP/COEP gives the page a cross-origin-isolated context so the mesh /
	// server workers can use SharedArrayBuffer and high-resolution timers.
	cfg.cross_origin_isolation = cross_origin_isolation_ || (unpacked_ && enable_game_workers_);
	cfg.immutable_assets = unpacked_;
	cfg.control_handler = [this](const std::string &raw) -> std::string {
		// Runs on an HTTP worker thread.
		std::string cmd = raw, arg;
		size_t q = raw.find('?');
		if (q != std::string::npos) {
			cmd = raw.substr(0, q);
			arg = eagler::LocalHttpServer::url_decode(raw.substr(q + 1));
		}
		if (cmd == "log") {
			// Page diagnostics -> logcat (thread-safe, no engine objects touched).
			UtilityFunctions::print("[EaglerHost/page] ", String::utf8(arg.c_str(), static_cast<int>(arg.size())));
			if (arg.rfind("stage game-ready", 0) == 0) {
				page_ready_.store(true);
			}
			return "{\"ok\":true}";
		}
		// Everything else hops to the main thread.
		call_deferred("_on_page_command", String(cmd.c_str()));
		return "{\"ok\":true}";
	};
	cfg.worker_threads = worker_threads_ > 0 ? static_cast<unsigned>(worker_threads_) : 0;
	std::string err;
	if (!server_->start(cfg, &err)) {
		_set_error(String("HTTP server failed: ") + err.c_str());
		return false;
	}
	state_.store(STATE_SERVING);
	_log(String("Serving ") + web_root_.c_str() + " at " + server_->base_url().c_str() +
			" with " + String::num_int64(server_->worker_count()) + " worker threads");
	emit_signal("server_started", String(server_->base_url().c_str()));
	return true;
}

// ---------------------------------------------------------------------------
// Android WebView (UI thread)
// ---------------------------------------------------------------------------

void EaglerHost::_run_on_ui_thread(const Callable &p_callable) {
	if (!is_android_ || android_runtime_ == nullptr || activity_.is_null()) {
		return;
	}
	Variant runnable = android_runtime_->call("createRunnableFromGodotCallable", p_callable);
	activity_->call("runOnUiThread", runnable);
}

void EaglerHost::_request_webview() {
	if (!is_android_ || webview_requested_) {
		return;
	}
	webview_requested_ = true;
	_run_on_ui_thread(Callable(this, "_ui_create_webview"));
}

void EaglerHost::_ui_create_webview() {
	JavaClassWrapper *jcw = JavaClassWrapper::get_singleton();
	Ref<JavaClass> WebView = jcw->wrap("android.webkit.WebView");
	Ref<JavaClass> WebViewClient = jcw->wrap("android.webkit.WebViewClient");
	Ref<JavaClass> WebChromeClient = jcw->wrap("android.webkit.WebChromeClient");
	Ref<JavaClass> LayoutParams = jcw->wrap("android.view.ViewGroup$LayoutParams");
	Ref<JavaClass> Color = jcw->wrap("android.graphics.Color");
	if (WebView.is_null() || LayoutParams.is_null()) {
		_set_error("android.webkit.WebView is not available on this device.");
		return;
	}

	// Chromium WebView: force the GPU compositor path for the whole content.
	WebView->call("setWebContentsDebuggingEnabled", OS::get_singleton()->is_debug_build());

	Ref<JavaObject> wv = WebView->call("WebView", activity_);
	if (wv.is_null()) {
		Ref<JavaObject> ex = jcw->get_exception();
		_set_error(String("WebView constructor failed: ") + (ex.is_valid() ? String(ex->call("toString")) : String("unknown")));
		return;
	}
	webview_ = wv;

	// Hardware-accelerated layer for the view itself.
	if (use_hardware_layer_) {
		wv->call("setLayerType", kLayerTypeHardware, Variant());
	}
	if (Color.is_valid()) {
		wv->call("setBackgroundColor", Color->get("BLACK"));
	}
	wv->call("setFocusable", true);
	wv->call("setFocusableInTouchMode", true);
	wv->call("setOverScrollMode", 2 /*OVER_SCROLL_NEVER*/);
	wv->call("setVerticalScrollBarEnabled", false);
	wv->call("setHorizontalScrollBarEnabled", false);

	// WebSettings: JS + WebGL + storage + audio autoplay + zoom off.
	Ref<JavaObject> settings = wv->call("getSettings");
	if (settings.is_valid()) {
		settings->call("setJavaScriptEnabled", true);
		settings->call("setDomStorageEnabled", true);
		settings->call("setDatabaseEnabled", true);
		settings->call("setAllowFileAccess", false);
		settings->call("setAllowContentAccess", false);
		settings->call("setMediaPlaybackRequiresUserGesture", false);
		settings->call("setJavaScriptCanOpenWindowsAutomatically", false);
		settings->call("setSupportZoom", false);
		settings->call("setBuiltInZoomControls", false);
		settings->call("setDisplayZoomControls", false);
		settings->call("setUseWideViewPort", true);
		settings->call("setLoadWithOverviewMode", true);
		settings->call("setMixedContentMode", kMixedContentCompat);
		// Fully offline: everything comes from the loopback server; never
		// stall on a (non-existent) network connection.
		settings->call("setCacheMode", offline_only_ ? kCacheLoadCacheElseNetwork : kCacheLoadDefault);
		settings->call("setBlockNetworkLoads", false); // must stay false for 127.0.0.1
		settings->call("setGeolocationEnabled", false);
		settings->call("setSafeBrowsingEnabled", false);
		settings->call("setOffscreenPreRaster", true);
	}

	if (WebViewClient.is_valid()) {
		Ref<JavaObject> client = WebViewClient->call("WebViewClient");
		if (client.is_valid()) {
			wv->call("setWebViewClient", client);
		}
	}
	if (WebChromeClient.is_valid()) {
		Ref<JavaObject> chrome = WebChromeClient->call("WebChromeClient");
		if (chrome.is_valid()) {
			wv->call("setWebChromeClient", chrome);
		}
	}

	// Keep the WebView's Java heap and GPU budget generous: this is the only
	// UI in the app, so nothing else needs it.
	wv->call("setDrawingCacheEnabled", false);
	wv->call("setKeepScreenOn", true);

	// Attach above Godot's Vulkan SurfaceView (full-screen).
	// Constructor name for nested classes is "Outer$Inner" (JavaClassWrapper convention).
	Ref<JavaObject> lp = LayoutParams->call("ViewGroup$LayoutParams", kMatchParent, kMatchParent);
	activity_->call("addContentView", wv, lp);
	wv->call("requestFocus");

	_apply_immersive_mode();

	const String url = _page_url();
	wv->call("loadUrl", url);
	// The offline guard is (re-)injected from _process() once the page has
	// installed its own fetch shim, see _tick_offline_guard().

	state_.store(STATE_WEBVIEW_READY);
	_log("WebView attached, loading " + url);
	// Godot's Vulkan swapchain sits underneath an opaque WebView; cap its
	// frame rate so the GPU/CPU budget goes to the game's WebGL context.
	call_deferred("_throttle_host_renderer");
	call_deferred("emit_signal", "webview_ready");
}

void EaglerHost::_throttle_host_renderer() {
	Engine::get_singleton()->set_max_fps(host_fps_when_hidden_);
	OS::get_singleton()->set_low_processor_usage_mode(true);
	OS::get_singleton()->set_low_processor_usage_mode_sleep_usec(16000);
}

void EaglerHost::_apply_immersive_mode() {
	if (!immersive_ || activity_.is_null()) {
		return;
	}
	JavaClassWrapper *jcw = JavaClassWrapper::get_singleton();
	Ref<JavaObject> window = activity_->call("getWindow");
	if (window.is_null()) {
		return;
	}

	// Window flags: keep screen on, draw behind system bars, fullscreen.
	window->call("addFlags", 0x00000080 /*FLAG_KEEP_SCREEN_ON*/);
	window->call("addFlags", 0x00000400 /*FLAG_FULLSCREEN*/);
	window->call("clearFlags", 0x00000800 /*FLAG_FORCE_NOT_FULLSCREEN*/);
	window->call("addFlags", 0x80000000 /*FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS*/);
	window->call("clearFlags", 0x04000000 /*FLAG_TRANSLUCENT_STATUS*/);
	window->call("clearFlags", 0x08000000 /*FLAG_TRANSLUCENT_NAVIGATION*/);
	window->call("setStatusBarColor", 0xFF000000);
	window->call("setNavigationBarColor", 0xFF000000);

	const int sdk = _android_sdk_int();

	// Draw into the display cutout (notch) area: Android 9+.
	if (sdk >= 28) {
		Ref<JavaObject> attrs = window->call("getAttributes");
		if (attrs.is_valid()) {
			// LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES = 1, ALWAYS = 3 (API 30+).
			attrs->set("layoutInDisplayCutoutMode", sdk >= 30 ? 3 : 1);
			window->call("setAttributes", attrs);
		}
	}

	// Android 11+: WindowInsetsController API (the legacy flags are ignored
	// on some OEM builds once targetSdk >= 30).
	bool modern_ok = false;
	if (sdk >= 30) {
		window->call("setDecorFitsSystemWindows", false);
		Ref<JavaObject> controller = window->call("getInsetsController");
		if (controller.is_valid()) {
			Ref<JavaClass> Type = jcw->wrap("android.view.WindowInsets$Type");
			int bars = 0;
			if (Type.is_valid()) {
				bars = int(Type->call("systemBars")) | int(Type->call("displayCutout"));
			} else {
				bars = 0x7; // statusBars|navigationBars|captionBar
			}
			controller->call("hide", bars);
			// BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE = 2 (sticky immersive).
			controller->call("setSystemBarsBehavior", 2);
			modern_ok = true;
		}
	}

	// Legacy sticky-immersive flags (all versions; harmless on 11+ and still
	// the only path on 7-10).
	Ref<JavaObject> decor = window->call("getDecorView");
	if (decor.is_valid()) {
		decor->call("setSystemUiVisibility", kImmersiveFlags);
		if (!modern_ok) {
			// Re-assert whenever the system UI becomes visible again (e.g. after
			// the keyboard closes) by polling from _process; see _tick_fullscreen.
			fullscreen_dirty_ = true;
		}
	}

	// Make sure the WebView itself spans the whole window incl. behind bars.
	if (webview_.is_valid()) {
		webview_->call("setFitsSystemWindows", false);
		webview_->call("setSystemUiVisibility", kImmersiveFlags);
	}
}

int EaglerHost::_android_sdk_int() {
	if (sdk_int_ >= 0) {
		return sdk_int_;
	}
	sdk_int_ = 0;
	Ref<JavaClass> Version = JavaClassWrapper::get_singleton()->wrap("android.os.Build$VERSION");
	if (Version.is_valid()) {
		sdk_int_ = int(Version->get("SDK_INT"));
	}
	return sdk_int_;
}

void EaglerHost::_ui_reapply_fullscreen() {
	_apply_immersive_mode();
}

void EaglerHost::_ui_destroy_webview() {
	if (webview_.is_null()) {
		return;
	}
	Ref<JavaObject> parent = webview_->call("getParent");
	if (parent.is_valid()) {
		parent->call("removeView", webview_);
	}
	webview_->call("destroy");
	webview_.unref();
}

void EaglerHost::_ui_load_url(const String &p_url) {
	if (webview_.is_valid()) {
		webview_->call("loadUrl", p_url);
	}
}

void EaglerHost::_ui_eval_js(const String &p_script) {
	if (webview_.is_valid()) {
		webview_->call("evaluateJavascript", p_script, Variant());
	}
}

void EaglerHost::_ui_pause() {
	if (webview_.is_valid()) {
		webview_->call("onPause");
		webview_->call("pauseTimers");
	}
}

void EaglerHost::_ui_resume() {
	if (webview_.is_valid()) {
		webview_->call("resumeTimers");
		webview_->call("onResume");
		_apply_immersive_mode();
	}
}

void EaglerHost::_ui_back() {
	if (webview_.is_valid() && bool(webview_->call("canGoBack"))) {
		webview_->call("goBack");
	}
}

// ---------------------------------------------------------------------------
// In-page banner + updater bridge
// ---------------------------------------------------------------------------

static String _js_string(const String &p) {
	return "\"" + p.json_escape() + "\"";
}

void EaglerHost::show_banner(const String &p_message, const Dictionary &p_buttons) {
	// p_buttons: { "Label": "command", ... }; first entry is the primary one.
	String buttons;
	Array keys = p_buttons.keys();
	for (int i = 0; i < keys.size(); ++i) {
		buttons += "btn(" + _js_string(keys[i]) + "," + _js_string(p_buttons[keys[i]]) + "," + (i == 0 ? "true" : "false") + ");";
	}
	String js = String(kUpdateBannerJs).replace("__MSG__", _js_string(p_message)).replace("__BUTTONS__", buttons);
	evaluate_javascript(js);
}

void EaglerHost::hide_banner() {
	evaluate_javascript("(function(){var b=document.getElementById('__eagler_update_banner');if(b)b.remove();})();");
}

void EaglerHost::_on_page_command(const String &p_command) {
	emit_signal("page_command", p_command);
	Node *upd = get_node_or_null(NodePath("AppUpdater"));
	if (p_command == "update_download" && upd) {
		upd->call("download_update");
		show_banner("Downloading update…", Dictionary());
	} else if (p_command == "update_install" && upd) {
		upd->call("install_update");
	} else if (p_command == "update_check" && upd) {
		upd->call("check_for_update");
	} else if (p_command == "dismiss") {
		hide_banner();
	}
}

void EaglerHost::_on_update_available(const String &p_version, const String &) {
	Dictionary b;
	b["Update"] = "update_download";
	b["Later"] = "dismiss";
	show_banner("EaglerCraft " + p_version + " is available.", b);
}

void EaglerHost::_on_update_progress(int64_t p_bytes, int64_t p_total) {
	String pct = p_total > 0 ? String::num_int64(p_bytes * 100 / p_total) + "%" : String::num_int64(p_bytes / 1048576) + " MB";
	evaluate_javascript(String(kUpdateProgressJs).replace("__PCT__", _js_string(pct)));
}

void EaglerHost::_on_update_downloaded(const String &) {
	Dictionary b;
	b["Install"] = "update_install";
	b["Later"] = "dismiss";
	show_banner("Update downloaded. Install now? (the app will restart)", b);
}

void EaglerHost::_on_update_error(const String &p_message) {
	Dictionary b;
	b["Retry"] = "update_check";
	b["Dismiss"] = "dismiss";
	show_banner("Update failed: " + p_message, b);
}

void EaglerHost::_connect_updater() {
	Node *upd = get_node_or_null(NodePath("AppUpdater"));
	if (!upd) {
		return;
	}
	upd->connect("update_available", Callable(this, "_on_update_available"));
	upd->connect("download_progress", Callable(this, "_on_update_progress"));
	upd->connect("download_finished", Callable(this, "_on_update_downloaded"));
	upd->connect("update_error", Callable(this, "_on_update_error"));
}

// ---------------------------------------------------------------------------
// Public runtime API
// ---------------------------------------------------------------------------

void EaglerHost::reload() {
	guard_injections_ = 0;
	guard_timer_ = 0.0;
	page_ready_.store(false);
	watchdog_dumps_ = 0;
	watchdog_timer_ = 0.0;
	if (is_android_ && webview_.is_valid()) {
		_run_on_ui_thread(Callable(this, "_ui_load_url").bind(_page_url()));
	}
}

void EaglerHost::evaluate_javascript(const String &p_script) {
	if (is_android_ && webview_.is_valid()) {
		_run_on_ui_thread(Callable(this, "_ui_eval_js").bind(p_script));
	}
}

} // namespace godot
