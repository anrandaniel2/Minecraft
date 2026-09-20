// SPDX-License-Identifier: MIT
//
// LocalHttpServer - a small, multithreaded, loopback-only static file server.
//
// The Android WebView cannot read files out of Godot's PCK/APK, and file://
// origins are heavily restricted in Chromium (no fetch(), flaky IndexedDB,
// no streaming WASM compilation). So the extracted EaglerCraft bundle is
// served over http://127.0.0.1:<port>/ from inside the process.
//
// Design:
//   * One acceptor thread (blocking accept()).
//   * A fixed pool of N worker threads pulling accepted sockets from a queue.
//   * Each worker handles keep-alive requests for its socket until the peer
//     closes or a timeout hits.
//   * Only GET / HEAD are supported, with single-range support for media.
//
// This file intentionally has zero Godot dependencies.

#pragma once

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <mutex>
#include <string>
#include <thread>
#include <functional>
#include <vector>

namespace eagler {

class LocalHttpServer {
public:
	struct Config {
		std::string root_dir; // Absolute path to the directory to serve.
		std::string index_file = "index.html"; // Served for "/".
		uint16_t port = 0; // 0 = ephemeral, chosen by the kernel.
		unsigned worker_threads = 0; // 0 = hardware_concurrency (min 2).
		bool cross_origin_isolation = false; // COOP/COEP headers (SharedArrayBuffer).
		int keep_alive_timeout_sec = 15;
		bool immutable_assets = false; // Long-lived caching for non-HTML files.
		// Optional: requests to "/__host/<command>" are routed here (from any
		// worker thread) instead of the filesystem. Return the response body.
		std::function<std::string(const std::string &command)> control_handler;
	};

	LocalHttpServer();
	~LocalHttpServer();

	LocalHttpServer(const LocalHttpServer &) = delete;
	LocalHttpServer &operator=(const LocalHttpServer &) = delete;

	// Binds 127.0.0.1 and starts the threads. Returns false on failure.
	bool start(const Config &config, std::string *error_out = nullptr);
	void stop();

	bool is_running() const { return running_.load(); }
	uint16_t port() const { return bound_port_; }
	std::string base_url() const;

	// Statistics (for the debug overlay / logs).
	uint64_t requests_served() const { return requests_.load(); }
	uint64_t bytes_sent() const { return bytes_sent_.load(); }
	unsigned worker_count() const { return static_cast<unsigned>(workers_.size()); }

private:
	void accept_loop();
	void worker_loop();
	void handle_connection(int fd);
	bool handle_one_request(int fd, bool *keep_alive);

	bool send_all(int fd, const char *data, size_t len);
	bool send_response(int fd, int status, const char *reason,
			const std::string &content_type, const char *body, size_t body_len,
			bool head_only, const std::string &extra_headers = std::string());
	bool send_file(int fd, const std::string &path, const std::string &content_type,
			bool head_only, const std::string &range_header);

	std::string common_headers(bool cacheable) const;
	static std::string sanitize_path(const std::string &raw_target);

	Config config_;
	int listen_fd_ = -1;
	uint16_t bound_port_ = 0;

	std::atomic<bool> running_{ false };
	std::thread acceptor_;
	std::vector<std::thread> workers_;

	std::mutex queue_mutex_;
	std::condition_variable queue_cv_;
	std::deque<int> pending_;

	std::atomic<uint64_t> requests_{ 0 };
	std::atomic<uint64_t> bytes_sent_{ 0 };
};

// Looks up a MIME type by file extension (lower-cased, without dot).
const char *mime_type_for_extension(const std::string &ext);

} // namespace eagler
