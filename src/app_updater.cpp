// SPDX-License-Identifier: MIT

#include "app_updater.h"

#include <godot_cpp/classes/dir_access.hpp>
#include <godot_cpp/classes/engine.hpp>
#include <godot_cpp/classes/file_access.hpp>
#include <godot_cpp/classes/java_class.hpp>
#include <godot_cpp/classes/java_class_wrapper.hpp>
#include <godot_cpp/classes/json.hpp>
#include <godot_cpp/classes/os.hpp>
#include <godot_cpp/classes/project_settings.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/utility_functions.hpp>

namespace godot {

namespace {
constexpr const char *kUserAgent = "EaglerCraft-GodotHost-Updater";
constexpr int kHttpTimeoutMs = 20000;
constexpr int kChunk = 256 * 1024;
} // namespace

// JavaObject exposes methods only (no fields), so public static fields are
// read through java.lang.reflect.
static int _java_static_int(const String &p_class, const String &p_field, int p_default) {
	JavaClassWrapper *jcw = JavaClassWrapper::get_singleton();
	Ref<JavaClass> Class = jcw->wrap("java.lang.Class");
	if (Class.is_null()) {
		return p_default;
	}
	Ref<JavaObject> cls = Class->call("forName", p_class);
	if (cls.is_null()) {
		return p_default;
	}
	Ref<JavaObject> field = cls->call("getField", p_field);
	if (field.is_null()) {
		return p_default;
	}
	Variant v = field->call("getInt", Variant());
	return v.get_type() == Variant::INT ? int(v) : p_default;
}

AppUpdater::AppUpdater() {
	is_android_ = OS::get_singleton() && OS::get_singleton()->get_name() == "Android";
}

AppUpdater::~AppUpdater() {
	cancel_.store(true);
	if (worker_.joinable()) {
		worker_.join();
	}
}

void AppUpdater::_bind_methods() {
	ClassDB::bind_method(D_METHOD("set_repository", "owner_slash_repo"), &AppUpdater::set_repository);
	ClassDB::bind_method(D_METHOD("get_repository"), &AppUpdater::get_repository);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "repository"), "set_repository", "get_repository");
	ClassDB::bind_method(D_METHOD("set_asset_pattern", "glob"), &AppUpdater::set_asset_pattern);
	ClassDB::bind_method(D_METHOD("get_asset_pattern"), &AppUpdater::get_asset_pattern);
	ADD_PROPERTY(PropertyInfo(Variant::STRING, "asset_pattern"), "set_asset_pattern", "get_asset_pattern");
	ClassDB::bind_method(D_METHOD("set_auto_check", "enabled"), &AppUpdater::set_auto_check);
	ClassDB::bind_method(D_METHOD("get_auto_check"), &AppUpdater::get_auto_check);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "auto_check"), "set_auto_check", "get_auto_check");
	ClassDB::bind_method(D_METHOD("set_auto_check_interval_hours", "hours"), &AppUpdater::set_auto_check_interval_hours);
	ClassDB::bind_method(D_METHOD("get_auto_check_interval_hours"), &AppUpdater::get_auto_check_interval_hours);
	ADD_PROPERTY(PropertyInfo(Variant::INT, "auto_check_interval_hours", PROPERTY_HINT_RANGE, "1,720,1"), "set_auto_check_interval_hours", "get_auto_check_interval_hours");
	ClassDB::bind_method(D_METHOD("set_allow_prerelease", "enabled"), &AppUpdater::set_allow_prerelease);
	ClassDB::bind_method(D_METHOD("get_allow_prerelease"), &AppUpdater::get_allow_prerelease);
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "allow_prerelease"), "set_allow_prerelease", "get_allow_prerelease");

	ClassDB::bind_method(D_METHOD("check_for_update"), &AppUpdater::check_for_update);
	ClassDB::bind_method(D_METHOD("download_update"), &AppUpdater::download_update);
	ClassDB::bind_method(D_METHOD("install_update"), &AppUpdater::install_update);
	ClassDB::bind_method(D_METHOD("cancel"), &AppUpdater::cancel);

	ClassDB::bind_method(D_METHOD("get_state"), &AppUpdater::get_state);
	ClassDB::bind_method(D_METHOD("get_current_version"), &AppUpdater::get_current_version);
	ClassDB::bind_method(D_METHOD("get_current_version_code"), &AppUpdater::get_current_version_code);
	ClassDB::bind_method(D_METHOD("get_latest_version"), &AppUpdater::get_latest_version);
	ClassDB::bind_method(D_METHOD("get_release_notes"), &AppUpdater::get_release_notes);
	ClassDB::bind_method(D_METHOD("get_download_url"), &AppUpdater::get_download_url);
	ClassDB::bind_method(D_METHOD("get_download_size"), &AppUpdater::get_download_size);
	ClassDB::bind_method(D_METHOD("get_downloaded_bytes"), &AppUpdater::get_downloaded_bytes);
	ClassDB::bind_method(D_METHOD("get_last_error"), &AppUpdater::get_last_error);
	ClassDB::bind_method(D_METHOD("get_downloaded_apk_path"), &AppUpdater::get_downloaded_apk_path);
	ClassDB::bind_method(D_METHOD("_ui_install", "apk_path"), &AppUpdater::_ui_install);

	ADD_SIGNAL(MethodInfo("update_available", PropertyInfo(Variant::STRING, "version"), PropertyInfo(Variant::STRING, "notes")));
	ADD_SIGNAL(MethodInfo("up_to_date"));
	ADD_SIGNAL(MethodInfo("download_progress", PropertyInfo(Variant::INT, "bytes"), PropertyInfo(Variant::INT, "total")));
	ADD_SIGNAL(MethodInfo("download_finished", PropertyInfo(Variant::STRING, "apk_path")));
	ADD_SIGNAL(MethodInfo("update_error", PropertyInfo(Variant::STRING, "message")));
	ADD_SIGNAL(MethodInfo("state_changed", PropertyInfo(Variant::INT, "state")));

	BIND_ENUM_CONSTANT(UPDATER_IDLE);
	BIND_ENUM_CONSTANT(UPDATER_CHECKING);
	BIND_ENUM_CONSTANT(UPDATER_UPDATE_AVAILABLE);
	BIND_ENUM_CONSTANT(UPDATER_UP_TO_DATE);
	BIND_ENUM_CONSTANT(UPDATER_DOWNLOADING);
	BIND_ENUM_CONSTANT(UPDATER_READY_TO_INSTALL);
	BIND_ENUM_CONSTANT(UPDATER_INSTALLING);
	BIND_ENUM_CONSTANT(UPDATER_ERROR);
}

// --- Properties -------------------------------------------------------------

void AppUpdater::set_repository(const String &p) { repository_ = p; }
String AppUpdater::get_repository() const { return repository_; }
void AppUpdater::set_asset_pattern(const String &p) { asset_pattern_ = p; }
String AppUpdater::get_asset_pattern() const { return asset_pattern_; }
void AppUpdater::set_auto_check(bool p) { auto_check_ = p; }
bool AppUpdater::get_auto_check() const { return auto_check_; }
void AppUpdater::set_auto_check_interval_hours(int p) { auto_check_interval_hours_ = p; }
int AppUpdater::get_auto_check_interval_hours() const { return auto_check_interval_hours_; }
void AppUpdater::set_allow_prerelease(bool p) { allow_prerelease_ = p; }
bool AppUpdater::get_allow_prerelease() const { return allow_prerelease_; }

String AppUpdater::get_current_version() const { return current_version_; }
int AppUpdater::get_current_version_code() const { return current_version_code_; }
String AppUpdater::get_latest_version() const {
	std::lock_guard<std::mutex> l(mutex_);
	return latest_.version;
}
String AppUpdater::get_release_notes() const {
	std::lock_guard<std::mutex> l(mutex_);
	return latest_.notes;
}
String AppUpdater::get_download_url() const {
	std::lock_guard<std::mutex> l(mutex_);
	return latest_.apk_url;
}
int64_t AppUpdater::get_download_size() const {
	std::lock_guard<std::mutex> l(mutex_);
	return latest_.apk_size;
}
String AppUpdater::get_last_error() const {
	std::lock_guard<std::mutex> l(mutex_);
	return last_error_;
}
String AppUpdater::get_downloaded_apk_path() const {
	std::lock_guard<std::mutex> l(mutex_);
	return apk_path_;
}

// --- Lifecycle --------------------------------------------------------------

void AppUpdater::_ready() {
	if (Engine::get_singleton()->is_editor_hint()) {
		return;
	}
	if (is_android_ && Engine::get_singleton()->has_singleton("AndroidRuntime")) {
		android_runtime_ = Engine::get_singleton()->get_singleton("AndroidRuntime");
		activity_ = android_runtime_->call("getActivity");
	}
	if (is_android_) {
		sdk_int_ = _java_static_int("android.os.Build$VERSION", "SDK_INT", 0);
	}
	_read_package_info();
	set_process(true);
	UtilityFunctions::print("[AppUpdater] running version ", current_version_, " (", current_version_code_, ") repo ", repository_);
	if (auto_check_) {
		check_for_update();
	}
}

void AppUpdater::_process(double p_delta) {
	if (thread_done_.load()) {
		_finish_thread();
	}
	if (auto_check_ && checked_once_) {
		auto_check_timer_ += p_delta;
		if (auto_check_timer_ >= auto_check_interval_hours_ * 3600.0) {
			auto_check_timer_ = 0.0;
			check_for_update();
		}
	}
	if (state_.load() == UPDATER_DOWNLOADING) {
		emit_signal("download_progress", downloaded_.load(), get_download_size());
	}
}

void AppUpdater::_exit_tree() {
	cancel_.store(true);
}

void AppUpdater::_read_package_info() {
	// The build stamps the same version into project.godot and the APK
	// manifest (see .github/workflows/build-apk.yml "Stamp version").
	current_version_ = ProjectSettings::get_singleton()->get_setting("application/config/version", "0.0.0");
	if (!is_android_ || activity_.is_null()) {
		return;
	}
	Ref<JavaObject> pm = activity_->call("getPackageManager");
	String pkg = activity_->call("getPackageName");
	if (pm.is_valid()) {
		Ref<JavaObject> info = pm->call("getPackageInfo", pkg, 0);
		if (info.is_valid() && sdk_int_ >= 28) {
			current_version_code_ = int(int64_t(info->call("getLongVersionCode")));
		}
	}
}

String AppUpdater::_update_dir() {
	String dir;
	if (is_android_ && activity_.is_valid()) {
		Ref<JavaObject> f = activity_->call("getExternalCacheDir");
		if (f.is_null()) {
			f = activity_->call("getCacheDir");
		}
		if (f.is_valid()) {
			dir = String(f->call("getAbsolutePath")) + "/update";
		}
	}
	if (dir.is_empty()) {
		dir = ProjectSettings::get_singleton()->globalize_path("user://update");
	}
	DirAccess::make_dir_recursive_absolute(dir);
	return dir;
}

void AppUpdater::_set_state(int p_state) {
	state_.store(p_state);
	call_deferred("emit_signal", "state_changed", p_state);
}

void AppUpdater::_set_error(const String &p_msg) {
	{
		std::lock_guard<std::mutex> l(mutex_);
		last_error_ = p_msg;
	}
	UtilityFunctions::push_warning("[AppUpdater] ", p_msg);
	_set_state(UPDATER_ERROR);
	call_deferred("emit_signal", "update_error", p_msg);
}

// --- Version helpers --------------------------------------------------------

String AppUpdater::_normalize_version(const String &p_tag) {
	String v = p_tag.strip_edges();
	if (v.begins_with("v") || v.begins_with("V")) {
		v = v.substr(1);
	}
	// Drop build metadata "+..." ; keep pre-release "-beta.1".
	int plus = v.find("+");
	if (plus >= 0) {
		v = v.substr(0, plus);
	}
	return v;
}

int AppUpdater::_compare_versions(const String &a, const String &b) {
	// Semver-ish: numeric dotted core, optional "-pre". Release > pre-release.
	auto split = [](const String &s, String &core, String &pre) {
		int dash = s.find("-");
		core = dash >= 0 ? s.substr(0, dash) : s;
		pre = dash >= 0 ? s.substr(dash + 1) : String();
	};
	String ca, pa, cb, pb;
	split(a, ca, pa);
	split(b, cb, pb);
	PackedStringArray xa = ca.split("."), xb = cb.split(".");
	int n = MAX(xa.size(), xb.size());
	for (int i = 0; i < n; ++i) {
		// missing segment -> 0 (so nightly 26.2.6.42 > release 26.2.6).
		int64_t va = i < xa.size() ? xa[i].to_int() : 0;
		int64_t vb = i < xb.size() ? xb[i].to_int() : 0;
		if (va != vb) {
			return va < vb ? -1 : 1;
		}
	}
	if (pa.is_empty() != pb.is_empty()) {
		return pa.is_empty() ? 1 : -1;
	}
	return pa.casecmp_to(pb);
}

// --- HTTP via java.net.HttpsURLConnection -----------------------------------

bool AppUpdater::_http_get_string(const String &p_url, String &r_body, String &r_err) {
	if (!is_android_) {
		r_err = "updater is Android-only";
		return false;
	}
	JavaClassWrapper *jcw = JavaClassWrapper::get_singleton();
	Ref<JavaClass> URL = jcw->wrap("java.net.URL");
	Ref<JavaObject> url = URL->call("URL", p_url);
	if (url.is_null()) {
		r_err = "bad URL";
		return false;
	}
	Ref<JavaObject> conn = url->call("openConnection");
	if (conn.is_null()) {
		r_err = "openConnection failed";
		return false;
	}
	conn->call("setRequestProperty", "User-Agent", kUserAgent);
	conn->call("setRequestProperty", "Accept", "application/vnd.github+json");
	conn->call("setConnectTimeout", kHttpTimeoutMs);
	conn->call("setReadTimeout", kHttpTimeoutMs);
	conn->call("setInstanceFollowRedirects", true);
	int code = int(conn->call("getResponseCode"));
	if (code < 200 || code >= 300) {
		r_err = "HTTP " + String::num_int64(code) + " for " + p_url;
		conn->call("disconnect");
		return false;
	}
	Ref<JavaObject> in = conn->call("getInputStream");
	if (in.is_null()) {
		r_err = "no body";
		return false;
	}
	// Read the (text) body line by line through a BufferedReader; works on
	// every API level and avoids marshalling byte[] through the wrapper.
	Ref<JavaClass> ISR = jcw->wrap("java.io.InputStreamReader");
	Ref<JavaClass> BR = jcw->wrap("java.io.BufferedReader");
	Ref<JavaObject> isr = ISR->call("InputStreamReader", in, "UTF-8");
	Ref<JavaObject> br = BR->call("BufferedReader", isr);
	String body;
	while (true) {
		Variant line = br->call("readLine");
		if (line.get_type() != Variant::STRING) {
			break;
		}
		body += String(line) + "\n";
	}
	br->call("close");
	r_body = body;
	in->call("close");
	conn->call("disconnect");
	return true;
}

bool AppUpdater::_http_download(const String &p_url, const String &p_dest, int64_t p_expected, String &r_err) {
	JavaClassWrapper *jcw = JavaClassWrapper::get_singleton();
	Ref<JavaClass> URL = jcw->wrap("java.net.URL");
	Ref<JavaObject> url = URL->call("URL", p_url);
	Ref<JavaObject> conn = url.is_valid() ? Ref<JavaObject>(url->call("openConnection")) : Ref<JavaObject>();
	if (conn.is_null()) {
		r_err = "openConnection failed";
		return false;
	}
	conn->call("setRequestProperty", "User-Agent", kUserAgent);
	conn->call("setRequestProperty", "Accept", "application/octet-stream");
	conn->call("setConnectTimeout", kHttpTimeoutMs);
	conn->call("setReadTimeout", kHttpTimeoutMs * 3);
	conn->call("setInstanceFollowRedirects", true);
	int code = int(conn->call("getResponseCode"));
	if (code < 200 || code >= 300) {
		r_err = "HTTP " + String::num_int64(code);
		return false;
	}
	Ref<JavaObject> in = conn->call("getInputStream");
	if (in.is_null()) {
		r_err = "no body";
		return false;
	}
	// Stream to disk in Java (FileOutputStream) chunk by chunk so we can
	// report progress and honour cancel without copying through Variant.
	Ref<JavaClass> FOS = jcw->wrap("java.io.FileOutputStream");
	Ref<JavaObject> out = FOS->call("FileOutputStream", p_dest);
	if (out.is_null()) {
		r_err = "cannot open " + p_dest;
		return false;
	}
	Ref<JavaClass> Channels = jcw->wrap("java.nio.channels.Channels");
	Ref<JavaObject> src = Channels->call("newChannel", in);
	Ref<JavaObject> dst = out->call("getChannel");
	Ref<JavaClass> ByteBuffer = jcw->wrap("java.nio.ByteBuffer");
	Ref<JavaObject> bb = ByteBuffer->call("allocateDirect", kChunk);
	int64_t total = 0;
	bool ok = true;
	while (!cancel_.load()) {
		bb->call("clear");
		int n = int(src->call("read", bb));
		if (n < 0) {
			break;
		}
		bb->call("flip");
		while (bool(bb->call("hasRemaining"))) {
			dst->call("write", bb);
		}
		total += n;
		downloaded_.store(total);
	}
	if (cancel_.load()) {
		ok = false;
		r_err = "cancelled";
	}
	src->call("close");
	dst->call("close");
	out->call("close");
	in->call("close");
	conn->call("disconnect");
	if (ok && p_expected > 0 && total != p_expected) {
		r_err = "size mismatch: got " + String::num_int64(total) + ", expected " + String::num_int64(p_expected);
		return false;
	}
	return ok;
}

bool AppUpdater::_parse_latest_release(const String &p_json, ReleaseInfo &r, String &r_err) {
	Variant parsed = JSON::parse_string(p_json);
	Array releases;
	if (parsed.get_type() == Variant::ARRAY) {
		releases = parsed;
	} else if (parsed.get_type() == Variant::DICTIONARY) {
		Dictionary d = parsed;
		if (d.has("message") && !d.has("tag_name")) {
			r_err = String("GitHub: ") + String(d["message"]);
			return false;
		}
		releases.push_back(d);
	} else {
		r_err = "invalid JSON from GitHub";
		return false;
	}

	// Pick the highest version among the eligible releases. The rolling
	// "nightly" pre-release keeps its tag, so its version lives in the name
	// ("Nightly 26.2.6.42"); tagged releases use the tag ("v26.2.7").
	bool found = false;
	for (int i = 0; i < releases.size(); ++i) {
		Dictionary d = releases[i];
		if (bool(d.get("draft", false))) {
			continue;
		}
		bool pre = bool(d.get("prerelease", false));
		if (pre && !allow_prerelease_) {
			continue;
		}
		ReleaseInfo c;
		c.tag = d.get("tag_name", "");
		c.version = _normalize_version(c.tag);
		if (c.version.is_empty() || !c.version.substr(0, 1).is_valid_int()) {
			String name = d.get("name", "");
			PackedStringArray words = name.split(" ");
			for (int w = 0; w < words.size(); ++w) {
				String cand = _normalize_version(words[w]);
				if (!cand.is_empty() && cand.substr(0, 1).is_valid_int()) {
					c.version = cand;
					break;
				}
			}
		}
		if (c.version.is_empty()) {
			continue;
		}
		c.notes = d.get("body", "");
		c.prerelease = pre;
		Array assets = d.get("assets", Array());
		for (int a = 0; a < assets.size(); ++a) {
			Dictionary asset = assets[a];
			String name = asset.get("name", "");
			if (name.ends_with(".sha256")) {
				if (c.sha256_url.is_empty()) {
					c.sha256_url = asset.get("browser_download_url", "");
				}
				continue;
			}
			if (c.apk_url.is_empty() && name.match(asset_pattern_)) {
				c.apk_url = asset.get("browser_download_url", "");
				c.apk_name = name;
				c.apk_size = int64_t(asset.get("size", 0));
			}
		}
		if (c.apk_url.is_empty()) {
			continue;
		}
		if (!found || _compare_versions(c.version, r.version) > 0) {
			r = c;
			found = true;
		}
	}
	if (!found) {
		r_err = "no release with an asset matching " + asset_pattern_;
		return false;
	}
	return true;
}

bool AppUpdater::_verify_sha256(const String &p_path, const String &p_expected_hex) {
	String actual = FileAccess::get_sha256(p_path);
	return actual.to_lower() == p_expected_hex.strip_edges().to_lower();
}

// --- Threads ----------------------------------------------------------------

void AppUpdater::check_for_update() {
	int s = state_.load();
	if (s == UPDATER_CHECKING || s == UPDATER_DOWNLOADING || s == UPDATER_INSTALLING) {
		return;
	}
	if (worker_.joinable()) {
		worker_.join();
	}
	checked_once_ = true;
	cancel_.store(false);
	thread_done_.store(false);
	_set_state(UPDATER_CHECKING);
	worker_ = std::thread(&AppUpdater::_check_thread_main, this);
}

void AppUpdater::_check_thread_main() {
	String url = "https://api.github.com/repos/" + repository_ + "/releases?per_page=20";
	String body, err;
	int next = UPDATER_ERROR;
	if (_http_get_string(url, body, err)) {
		ReleaseInfo info;
		if (_parse_latest_release(body, info, err)) {
			std::lock_guard<std::mutex> l(mutex_);
			latest_ = info;
			next = _compare_versions(info.version, _normalize_version(current_version_)) > 0
					? UPDATER_UPDATE_AVAILABLE
					: UPDATER_UP_TO_DATE;
		}
	}
	if (next == UPDATER_ERROR) {
		std::lock_guard<std::mutex> l(mutex_);
		last_error_ = err;
	}
	pending_state_.store(next);
	thread_done_.store(true);
}

void AppUpdater::download_update() {
	if (state_.load() != UPDATER_UPDATE_AVAILABLE && state_.load() != UPDATER_ERROR) {
		return;
	}
	if (get_download_url().is_empty()) {
		_set_error("no update to download (call check_for_update first)");
		return;
	}
	if (worker_.joinable()) {
		worker_.join();
	}
	cancel_.store(false);
	thread_done_.store(false);
	downloaded_.store(0);
	_set_state(UPDATER_DOWNLOADING);
	worker_ = std::thread(&AppUpdater::_download_thread_main, this);
}

void AppUpdater::_download_thread_main() {
	ReleaseInfo info;
	{
		std::lock_guard<std::mutex> l(mutex_);
		info = latest_;
	}
	String dir = _update_dir();
	String dest = dir + "/" + (info.apk_name.is_empty() ? String("update.apk") : info.apk_name);
	String err;
	int next = UPDATER_ERROR;
	if (_http_download(info.apk_url, dest, info.apk_size, err)) {
		bool verified = true;
		if (!info.sha256_url.is_empty()) {
			String sha;
			if (_http_get_string(info.sha256_url, sha, err)) {
				// "<hex>  <filename>" or bare hex.
				String hex = sha.strip_edges().split(" ")[0];
				verified = _verify_sha256(dest, hex);
				if (!verified) {
					err = "SHA-256 mismatch – download discarded";
					DirAccess::remove_absolute(dest);
				}
			} else {
				verified = true; // checksum unavailable; size check already passed
				err = String();
			}
		}
		if (verified) {
			std::lock_guard<std::mutex> l(mutex_);
			apk_path_ = dest;
			next = UPDATER_READY_TO_INSTALL;
		}
	}
	if (next == UPDATER_ERROR) {
		std::lock_guard<std::mutex> l(mutex_);
		last_error_ = err;
	}
	pending_state_.store(next);
	thread_done_.store(true);
}

void AppUpdater::_finish_thread() {
	thread_done_.store(false);
	if (worker_.joinable()) {
		worker_.join();
	}
	int next = pending_state_.exchange(-1);
	if (next < 0) {
		return;
	}
	_set_state(next);
	switch (next) {
		case UPDATER_UPDATE_AVAILABLE:
			emit_signal("update_available", get_latest_version(), get_release_notes());
			break;
		case UPDATER_UP_TO_DATE:
			emit_signal("up_to_date");
			break;
		case UPDATER_READY_TO_INSTALL:
			emit_signal("download_finished", get_downloaded_apk_path());
			break;
		case UPDATER_ERROR:
			emit_signal("update_error", get_last_error());
			break;
		default:
			break;
	}
}

void AppUpdater::cancel() {
	cancel_.store(true);
}

// --- Install (PackageInstaller session, UI thread) ---------------------------

void AppUpdater::install_update() {
	String path = get_downloaded_apk_path();
	if (path.is_empty() || !FileAccess::file_exists(path)) {
		_set_error("no downloaded APK to install");
		return;
	}
	if (!is_android_ || activity_.is_null() || android_runtime_ == nullptr) {
		_set_error("install is Android-only");
		return;
	}
	_set_state(UPDATER_INSTALLING);
	Variant runnable = android_runtime_->call("createRunnableFromGodotCallable", Callable(this, "_ui_install").bind(path));
	activity_->call("runOnUiThread", runnable);
}

void AppUpdater::_ui_install(const String &p_apk_path) {
	JavaClassWrapper *jcw = JavaClassWrapper::get_singleton();

	// Android 8+: the user must allow "install unknown apps" for this app.
	Ref<JavaObject> pm = activity_->call("getPackageManager");
	const int sdk = sdk_int_;
	if (sdk >= 26 && pm.is_valid() && !bool(pm->call("canRequestPackageInstalls"))) {
		Ref<JavaClass> Intent = jcw->wrap("android.content.Intent");
		Ref<JavaClass> Uri = jcw->wrap("android.net.Uri");
		Ref<JavaObject> uri = Uri->call("parse", "package:" + String(activity_->call("getPackageName")));
		Ref<JavaObject> intent = Intent->call("Intent", "android.settings.MANAGE_UNKNOWN_APP_SOURCES", uri);
		activity_->call("startActivity", intent);
		_set_error("Allow installs from this app in the settings screen that just opened, then tap Install again.");
		return;
	}

	// PackageInstaller session: streams the APK from our private cache
	// without needing a FileProvider entry in the manifest.
	Ref<JavaObject> installer = pm->call("getPackageInstaller");
	Ref<JavaClass> SessionParams = jcw->wrap("android.content.pm.PackageInstaller$SessionParams");
	Ref<JavaObject> params = SessionParams->call("PackageInstaller$SessionParams", 1 /*MODE_FULL_INSTALL*/);
	if (sdk >= 31) {
		params->call("setRequireUserAction", 2 /*USER_ACTION_NOT_REQUIRED*/);
	}
	int session_id = int(installer->call("createSession", params));
	Ref<JavaObject> session = installer->call("openSession", session_id);
	if (session.is_null()) {
		_set_error("PackageInstaller.openSession failed");
		return;
	}
	Ref<JavaClass> File = jcw->wrap("java.io.File");
	Ref<JavaObject> file = File->call("File", p_apk_path);
	int64_t size = int64_t(file->call("length"));
	Ref<JavaObject> out = session->call("openWrite", "base.apk", 0, size);
	Ref<JavaClass> FIS = jcw->wrap("java.io.FileInputStream");
	Ref<JavaObject> in = FIS->call("FileInputStream", file);
	Ref<JavaClass> Channels = jcw->wrap("java.nio.channels.Channels");
	Ref<JavaObject> src = in->call("getChannel");
	Ref<JavaObject> dst = Channels->call("newChannel", out);
	src->call("transferTo", 0, size, dst);
	session->call("fsync", out);
	out->call("close");
	in->call("close");

	// Status receiver: a PendingIntent that re-launches our own activity;
	// the system shows its own confirmation dialog first.
	Ref<JavaClass> Intent = jcw->wrap("android.content.Intent");
	Ref<JavaClass> PendingIntent = jcw->wrap("android.app.PendingIntent");
	Ref<JavaObject> intent = Intent->call("Intent", activity_, activity_->call("getClass"));
	intent->call("setAction", "net.eaglercraft.godothost.INSTALL_STATUS");
	int flags = 0x08000000 /*FLAG_UPDATE_CURRENT*/;
	if (sdk >= 31) {
		flags |= 0x02000000 /*FLAG_MUTABLE*/;
	}
	Ref<JavaObject> pi = PendingIntent->call("getActivity", activity_, session_id, intent, flags);
	Ref<JavaObject> sender = pi->call("getIntentSender");
	session->call("commit", sender);
	session->call("close");
	UtilityFunctions::print("[AppUpdater] install session ", session_id, " committed (", size, " bytes)");
}

} // namespace godot
