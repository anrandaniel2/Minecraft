// SPDX-License-Identifier: MIT

#include "local_http_server.h"

#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstring>

namespace eagler {

namespace {

constexpr size_t kMaxRequestBytes = 64 * 1024;
constexpr size_t kFileChunkBytes = 256 * 1024;

std::string to_lower(std::string s) {
	for (char &c : s) {
		if (c >= 'A' && c <= 'Z') {
			c = static_cast<char>(c - 'A' + 'a');
		}
	}
	return s;
}


} // namespace

std::string LocalHttpServer::url_decode(const std::string &in) {
	std::string out;
	out.reserve(in.size());
	for (size_t i = 0; i < in.size(); ++i) {
		if (in[i] == '%' && i + 2 < in.size()) {
			char hex[3] = { in[i + 1], in[i + 2], 0 };
			char *end = nullptr;
			long v = strtol(hex, &end, 16);
			if (end && *end == 0) {
				out.push_back(static_cast<char>(v));
				i += 2;
				continue;
			}
		}
		out.push_back(in[i]);
	}
	return out;
}

const char *mime_type_for_extension(const std::string &ext) {
	struct Entry {
		const char *ext;
		const char *mime;
	};
	static const Entry table[] = {
		{ "html", "text/html; charset=utf-8" },
		{ "htm", "text/html; charset=utf-8" },
		{ "js", "text/javascript; charset=utf-8" },
		{ "mjs", "text/javascript; charset=utf-8" },
		{ "css", "text/css; charset=utf-8" },
		{ "json", "application/json" },
		{ "wasm", "application/wasm" },
		{ "png", "image/png" },
		{ "jpg", "image/jpeg" },
		{ "jpeg", "image/jpeg" },
		{ "gif", "image/gif" },
		{ "webp", "image/webp" },
		{ "svg", "image/svg+xml" },
		{ "ico", "image/x-icon" },
		{ "ogg", "audio/ogg" },
		{ "oga", "audio/ogg" },
		{ "mp3", "audio/mpeg" },
		{ "wav", "audio/wav" },
		{ "mp4", "video/mp4" },
		{ "webm", "video/webm" },
		{ "txt", "text/plain; charset=utf-8" },
		{ "xml", "application/xml" },
		{ "zip", "application/zip" },
		{ "epk", "application/octet-stream" },
		{ "lang", "text/plain; charset=utf-8" },
		{ "ttf", "font/ttf" },
		{ "woff", "font/woff" },
		{ "woff2", "font/woff2" },
	};
	for (const Entry &e : table) {
		if (ext == e.ext) {
			return e.mime;
		}
	}
	return "application/octet-stream";
}

LocalHttpServer::LocalHttpServer() = default;

LocalHttpServer::~LocalHttpServer() {
	stop();
}

std::string LocalHttpServer::base_url() const {
	return "http://127.0.0.1:" + std::to_string(bound_port_) + "/";
}

bool LocalHttpServer::start(const Config &config, std::string *error_out) {
	if (running_.load()) {
		return true;
	}
	config_ = config;

	listen_fd_ = ::socket(AF_INET, SOCK_STREAM, 0);
	if (listen_fd_ < 0) {
		if (error_out) {
			*error_out = std::string("socket(): ") + strerror(errno);
		}
		return false;
	}
	int one = 1;
	setsockopt(listen_fd_, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

	sockaddr_in addr{};
	addr.sin_family = AF_INET;
	addr.sin_port = htons(config_.port);
	addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK); // Never expose on the network.

	if (::bind(listen_fd_, reinterpret_cast<sockaddr *>(&addr), sizeof(addr)) < 0) {
		if (error_out) {
			*error_out = std::string("bind(): ") + strerror(errno);
		}
		::close(listen_fd_);
		listen_fd_ = -1;
		return false;
	}
	if (::listen(listen_fd_, 64) < 0) {
		if (error_out) {
			*error_out = std::string("listen(): ") + strerror(errno);
		}
		::close(listen_fd_);
		listen_fd_ = -1;
		return false;
	}

	socklen_t len = sizeof(addr);
	if (::getsockname(listen_fd_, reinterpret_cast<sockaddr *>(&addr), &len) == 0) {
		bound_port_ = ntohs(addr.sin_port);
	} else {
		bound_port_ = config_.port;
	}

	// Chromium keeps up to 6 idle keep-alive sockets per host *per realm*
	// (page + every worker) and holds them for minutes. A fixed pool of N
	// threads with one blocking connection each therefore fills up with idle
	// sockets, and a new request (e.g. the server worker fetching
	// assets.epk) waits in the queue until an idle connection times out.
	// Loopback connections are cheap: use a thread per connection, with a
	// generous cap, and keep a small pool as spill-over.
	unsigned n = config_.worker_threads;
	if (n == 0) {
		n = std::thread::hardware_concurrency();
	}
	n = std::max(2u, std::min(n, 16u));

	running_.store(true);
	for (unsigned i = 0; i < n; ++i) {
		workers_.emplace_back(&LocalHttpServer::worker_loop, this);
	}
	acceptor_ = std::thread(&LocalHttpServer::accept_loop, this);
	return true;
}

void LocalHttpServer::stop() {
	if (!running_.exchange(false)) {
		return;
	}
	// Detached per-connection threads observe running_ == false at their
	// next poll() wake-up (bounded by keep_alive_timeout_sec).
	if (listen_fd_ >= 0) {
		::shutdown(listen_fd_, SHUT_RDWR);
		::close(listen_fd_);
		listen_fd_ = -1;
	}
	queue_cv_.notify_all();
	if (acceptor_.joinable()) {
		acceptor_.join();
	}
	for (std::thread &t : workers_) {
		if (t.joinable()) {
			t.join();
		}
	}
	workers_.clear();
	std::lock_guard<std::mutex> lock(queue_mutex_);
	for (int fd : pending_) {
		::close(fd);
	}
	pending_.clear();
}

void LocalHttpServer::accept_loop() {
	while (running_.load()) {
		sockaddr_in peer{};
		socklen_t len = sizeof(peer);
		int fd = ::accept(listen_fd_, reinterpret_cast<sockaddr *>(&peer), &len);
		if (fd < 0) {
			if (errno == EINTR) {
				continue;
			}
			break; // Socket closed by stop().
		}
		// Defense in depth: only loopback peers.
		if (peer.sin_addr.s_addr != htonl(INADDR_LOOPBACK)) {
			::close(fd);
			continue;
		}
		int one = 1;
		setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
		// Dedicated thread while under the cap; otherwise queue for the pool.
		if (active_connections_.load() < kMaxConnectionThreads) {
			active_connections_.fetch_add(1);
			try {
				std::thread([this, fd] {
					handle_connection(fd);
					::close(fd);
					active_connections_.fetch_sub(1);
				}).detach();
				continue;
			} catch (...) {
				active_connections_.fetch_sub(1);
			}
		}
		{
			std::lock_guard<std::mutex> lock(queue_mutex_);
			pending_.push_back(fd);
		}
		queue_cv_.notify_one();
	}
}

void LocalHttpServer::worker_loop() {
	while (true) {
		int fd = -1;
		{
			std::unique_lock<std::mutex> lock(queue_mutex_);
			queue_cv_.wait(lock, [this] { return !running_.load() || !pending_.empty(); });
			if (!running_.load() && pending_.empty()) {
				return;
			}
			fd = pending_.front();
			pending_.pop_front();
		}
		handle_connection(fd);
		::close(fd);
	}
}

void LocalHttpServer::handle_connection(int fd) {
	bool keep_alive = true;
	bool first = true;
	while (keep_alive && running_.load()) {
		pollfd p{};
		p.fd = fd;
		p.events = POLLIN;
		// First request must arrive quickly (Chromium preconnects and may
		// never use the socket); idle keep-alive gets the configured timeout.
		int r = ::poll(&p, 1, (first ? 5 : config_.keep_alive_timeout_sec) * 1000);
		first = false;
		if (r <= 0 || (p.revents & (POLLHUP | POLLERR))) {
			return;
		}
		if (!handle_one_request(fd, &keep_alive)) {
			return;
		}
	}
}

std::string LocalHttpServer::sanitize_path(const std::string &raw_target) {
	std::string target = raw_target;
	size_t q = target.find_first_of("?#");
	if (q != std::string::npos) {
		target.resize(q);
	}
	target = url_decode(target);

	// Split, drop "." and "..", rebuild.
	std::vector<std::string> parts;
	std::string cur;
	for (size_t i = 0; i <= target.size(); ++i) {
		if (i == target.size() || target[i] == '/' || target[i] == '\\') {
			if (cur == "..") {
				if (!parts.empty()) {
					parts.pop_back();
				}
			} else if (!cur.empty() && cur != ".") {
				parts.push_back(cur);
			}
			cur.clear();
		} else if (target[i] != 0) {
			cur.push_back(target[i]);
		}
	}
	std::string out;
	for (const std::string &p : parts) {
		out += "/";
		out += p;
	}
	return out; // "" means root.
}

std::string LocalHttpServer::common_headers(bool cacheable) const {
	std::string h;
	h += "Connection: keep-alive\r\n";
	// Big immutable payloads (wasm/epk) may be cached by Chromium, which also
	// lets it reuse compiled WebAssembly code across launches. HTML is not.
	h += (cacheable && config_.immutable_assets) ? "Cache-Control: public, max-age=31536000, immutable\r\n"
													: "Cache-Control: no-cache\r\n";
	h += "Access-Control-Allow-Origin: *\r\n";
	h += "X-Content-Type-Options: nosniff\r\n";
	if (config_.cross_origin_isolation) {
		h += "Cross-Origin-Opener-Policy: same-origin\r\n";
		h += "Cross-Origin-Embedder-Policy: require-corp\r\n";
		h += "Cross-Origin-Resource-Policy: cross-origin\r\n";
	}
	return h;
}

bool LocalHttpServer::send_all(int fd, const char *data, size_t len) {
	while (len > 0) {
		ssize_t n = ::send(fd, data, len, MSG_NOSIGNAL);
		if (n < 0) {
			if (errno == EINTR) {
				continue;
			}
			return false;
		}
		data += n;
		len -= static_cast<size_t>(n);
		bytes_sent_.fetch_add(static_cast<uint64_t>(n));
	}
	return true;
}

bool LocalHttpServer::send_response(int fd, int status, const char *reason,
		const std::string &content_type, const char *body, size_t body_len,
		bool head_only, const std::string &extra_headers) {
	std::string head = "HTTP/1.1 " + std::to_string(status) + " " + reason + "\r\n";
	head += "Content-Type: " + content_type + "\r\n";
	head += "Content-Length: " + std::to_string(body_len) + "\r\n";
	head += common_headers(false);
	head += extra_headers;
	head += "\r\n";
	if (!send_all(fd, head.data(), head.size())) {
		return false;
	}
	if (head_only || body_len == 0) {
		return true;
	}
	return send_all(fd, body, body_len);
}

bool LocalHttpServer::send_file(int fd, const std::string &path, const std::string &content_type,
		bool head_only, const std::string &range_header) {
	struct stat st{};
	if (::stat(path.c_str(), &st) != 0 || !S_ISREG(st.st_mode)) {
		static const char kNotFound[] = "404 Not Found";
		return send_response(fd, 404, "Not Found", "text/plain", kNotFound, sizeof(kNotFound) - 1, head_only);
	}
	const uint64_t size = static_cast<uint64_t>(st.st_size);

	uint64_t start = 0;
	uint64_t end = size == 0 ? 0 : size - 1;
	bool partial = false;
	if (!range_header.empty() && range_header.rfind("bytes=", 0) == 0 && size > 0) {
		std::string spec = range_header.substr(6);
		size_t dash = spec.find('-');
		if (dash != std::string::npos) {
			std::string a = spec.substr(0, dash);
			std::string b = spec.substr(dash + 1);
			if (a.empty() && !b.empty()) {
				uint64_t suffix = strtoull(b.c_str(), nullptr, 10);
				if (suffix > size) {
					suffix = size;
				}
				start = size - suffix;
				partial = true;
			} else if (!a.empty()) {
				start = strtoull(a.c_str(), nullptr, 10);
				if (!b.empty()) {
					end = strtoull(b.c_str(), nullptr, 10);
				}
				if (end >= size) {
					end = size - 1;
				}
				partial = true;
			}
			if (start > end || start >= size) {
				std::string extra = "Content-Range: bytes */" + std::to_string(size) + "\r\n";
				return send_response(fd, 416, "Range Not Satisfiable", "text/plain", "", 0, head_only, extra);
			}
		}
	}

	const uint64_t length = (size == 0) ? 0 : (end - start + 1);

	std::string head = partial ? "HTTP/1.1 206 Partial Content\r\n" : "HTTP/1.1 200 OK\r\n";
	head += "Content-Type: " + content_type + "\r\n";
	head += "Content-Length: " + std::to_string(length) + "\r\n";
	head += "Accept-Ranges: bytes\r\n";
	if (partial) {
		head += "Content-Range: bytes " + std::to_string(start) + "-" + std::to_string(end) + "/" + std::to_string(size) + "\r\n";
	}
	head += common_headers(content_type.rfind("text/html", 0) != 0);
	head += "\r\n";
	if (!send_all(fd, head.data(), head.size())) {
		return false;
	}
	if (head_only || length == 0) {
		return true;
	}

	int in = ::open(path.c_str(), O_RDONLY);
	if (in < 0) {
		return false;
	}
	if (start > 0) {
		::lseek(in, static_cast<off_t>(start), SEEK_SET);
	}
	std::vector<char> buf(kFileChunkBytes);
	uint64_t remaining = length;
	bool ok = true;
	while (remaining > 0 && ok) {
		size_t want = static_cast<size_t>(std::min<uint64_t>(remaining, buf.size()));
		ssize_t n = ::read(in, buf.data(), want);
		if (n <= 0) {
			ok = false;
			break;
		}
		ok = send_all(fd, buf.data(), static_cast<size_t>(n));
		remaining -= static_cast<uint64_t>(n);
	}
	::close(in);
	return ok;
}

bool LocalHttpServer::handle_one_request(int fd, bool *keep_alive) {
	std::string req;
	char buf[4096];
	// Read until end of headers.
	while (req.find("\r\n\r\n") == std::string::npos) {
		ssize_t n = ::recv(fd, buf, sizeof(buf), 0);
		if (n <= 0) {
			return false;
		}
		req.append(buf, static_cast<size_t>(n));
		if (req.size() > kMaxRequestBytes) {
			return false;
		}
	}

	// Request line.
	size_t eol = req.find("\r\n");
	std::string line = req.substr(0, eol);
	size_t sp1 = line.find(' ');
	size_t sp2 = line.find(' ', sp1 == std::string::npos ? 0 : sp1 + 1);
	if (sp1 == std::string::npos || sp2 == std::string::npos) {
		return false;
	}
	std::string method = line.substr(0, sp1);
	std::string target = line.substr(sp1 + 1, sp2 - sp1 - 1);
	std::string version = line.substr(sp2 + 1);

	// Headers of interest.
	std::string range;
	bool close_requested = (version == "HTTP/1.0");
	size_t pos = eol + 2;
	while (true) {
		size_t next = req.find("\r\n", pos);
		if (next == std::string::npos || next == pos) {
			break;
		}
		std::string h = req.substr(pos, next - pos);
		size_t colon = h.find(':');
		if (colon != std::string::npos) {
			std::string name = to_lower(h.substr(0, colon));
			std::string value = h.substr(colon + 1);
			while (!value.empty() && (value.front() == ' ' || value.front() == '\t')) {
				value.erase(value.begin());
			}
			if (name == "range") {
				range = value;
			} else if (name == "connection") {
				std::string v = to_lower(value);
				if (v.find("close") != std::string::npos) {
					close_requested = true;
				} else if (v.find("keep-alive") != std::string::npos) {
					close_requested = false;
				}
			}
		}
		pos = next + 2;
	}
	*keep_alive = !close_requested;
	requests_.fetch_add(1);

	const bool head_only = (method == "HEAD");
	if (method != "GET" && !head_only) {
		static const char kBody[] = "405 Method Not Allowed";
		return send_response(fd, 405, "Method Not Allowed", "text/plain", kBody, sizeof(kBody) - 1, head_only, "Allow: GET, HEAD\r\n");
	}

	// Control endpoint gets the *raw* target (command + query string) so the
	// page can pass arbitrary encoded text after '?'.
	if (target.rfind("/__host/", 0) == 0 && config_.control_handler) {
		std::string body = config_.control_handler(target.substr(8));
		return send_response(fd, 200, "OK", "application/json", body.data(), body.size(), head_only,
				"Cache-Control: no-store\r\n");
	}
	std::string rel = sanitize_path(target);
	if (rel.empty()) {
		rel = "/" + config_.index_file;
	}
	std::string full = config_.root_dir + rel;

	// If the target is a directory, serve its index.
	struct stat st{};
	if (::stat(full.c_str(), &st) == 0 && S_ISDIR(st.st_mode)) {
		full += "/" + config_.index_file;
	}

	std::string ext;
	size_t dot = full.find_last_of('.');
	size_t slash = full.find_last_of('/');
	if (dot != std::string::npos && (slash == std::string::npos || dot > slash)) {
		ext = to_lower(full.substr(dot + 1));
	}
	return send_file(fd, full, mime_type_for_extension(ext), head_only, range);
}

} // namespace eagler
