// SPDX-License-Identifier: MIT
//
// AppUpdater - in-app update via GitHub Releases, driven entirely from C++.
//
// Flow (all network calls go through Android's HttpsURLConnection via
// JavaClassWrapper on a worker thread, so the system trust store and the
// app's network-security-config apply):
//
//   check_for_update()  -> GET https://api.github.com/repos/<owner>/<repo>/releases/latest
//                          compare tag (vX.Y.Z or X.Y.Z) with the running versionName
//   download_update()   -> stream the .apk asset to <externalCacheDir>/update/<name>.apk
//                          verifying SHA-256 against the release's *.sha256 asset when present
//   install_update()    -> FileProvider-free install: ACTION_VIEW with
//                          content:// URI from the platform's own FileProvider is not
//                          available without manifest changes, so we use
//                          android.content.pm.PackageInstaller (session API), which
//                          works from any app on API 24+ with REQUEST_INSTALL_PACKAGES.
//
// The game stays fully offline: the updater only touches the network when the
// user explicitly triggers it (or when `auto_check` is enabled) and only
// contacts github.com / api.github.com / objects.githubusercontent.com.

#pragma once

#include <godot_cpp/classes/java_object.hpp>
#include <godot_cpp/classes/node.hpp>
#include <godot_cpp/classes/ref.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/string.hpp>

#include <atomic>
#include <mutex>
#include <string>
#include <thread>

namespace godot {

class AppUpdater : public Node {
	GDCLASS(AppUpdater, Node)

public:
	enum State {
		UPDATER_IDLE,
		UPDATER_CHECKING,
		UPDATER_UPDATE_AVAILABLE,
		UPDATER_UP_TO_DATE,
		UPDATER_DOWNLOADING,
		UPDATER_READY_TO_INSTALL,
		UPDATER_INSTALLING,
		UPDATER_ERROR,
	};

	AppUpdater();
	~AppUpdater() override;

	// Configuration --------------------------------------------------------
	void set_repository(const String &p_owner_slash_repo); // "owner/repo"
	String get_repository() const;
	void set_asset_pattern(const String &p_glob); // e.g. "*.apk"
	String get_asset_pattern() const;
	void set_auto_check(bool p_enabled);
	bool get_auto_check() const;
	void set_auto_check_interval_hours(int p_hours);
	int get_auto_check_interval_hours() const;
	void set_allow_prerelease(bool p_enabled);
	bool get_allow_prerelease() const;

	// Actions ---------------------------------------------------------------
	void check_for_update();
	void download_update();
	void install_update();
	void cancel();

	// Introspection ---------------------------------------------------------
	int get_state() const { return state_.load(); }
	String get_current_version() const;
	int get_current_version_code() const;
	String get_latest_version() const;
	String get_release_notes() const;
	String get_download_url() const;
	int64_t get_download_size() const;
	int64_t get_downloaded_bytes() const { return downloaded_.load(); }
	String get_last_error() const;
	String get_downloaded_apk_path() const;

	void _ready() override;
	void _process(double p_delta) override;
	void _exit_tree() override;

protected:
	static void _bind_methods();

private:
	struct ReleaseInfo {
		String tag;
		String version; // normalised, e.g. "1.2.3"
		String notes;
		String apk_url;
		String apk_name;
		String sha256_url;
		int64_t apk_size = 0;
		bool prerelease = false;
	};

	// Worker-thread helpers (Java HTTP through JavaClassWrapper).
	bool _http_get_string(const String &p_url, String &r_body, String &r_err);
	bool _http_download(const String &p_url, const String &p_dest, int64_t p_expected, String &r_err);
	bool _parse_latest_release(const String &p_json, ReleaseInfo &r_info, String &r_err);
	bool _verify_sha256(const String &p_path, const String &p_expected_hex);
	static int _compare_versions(const String &a, const String &b);
	static String _normalize_version(const String &p_tag);

	void _check_thread_main();
	void _download_thread_main();
	void _ui_install(const String &p_apk_path);
	void _finish_thread();
	void _set_state(int p_state);
	void _set_error(const String &p_msg);
	void _read_package_info();
	String _update_dir();

	// Config.
	String repository_ = "anrandaniel2/Minecraft";
	String asset_pattern_ = "*.apk";
	bool auto_check_ = false;
	int auto_check_interval_hours_ = 24;
	bool allow_prerelease_ = false;

	// State.
	std::atomic<int> state_{ UPDATER_IDLE };
	std::atomic<bool> cancel_{ false };
	std::atomic<int64_t> downloaded_{ 0 };
	std::atomic<bool> thread_done_{ false };
	std::atomic<int> pending_state_{ -1 };
	std::thread worker_;
	mutable std::mutex mutex_;
	ReleaseInfo latest_;
	String last_error_;
	String current_version_;
	int current_version_code_ = 0;
	int sdk_int_ = 0;
	String apk_path_;
	double auto_check_timer_ = 0.0;
	bool checked_once_ = false;

	bool is_android_ = false;
	Object *android_runtime_ = nullptr;
	Ref<JavaObject> activity_;
};

} // namespace godot

VARIANT_ENUM_CAST(godot::AppUpdater::State);
