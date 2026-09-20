// Standalone test for eagler::LocalHttpServer (no Godot needed).
//   g++ -std=c++17 -O2 -pthread -Isrc tests/http_server_test.cpp src/local_http_server.cpp -o /tmp/http_test && /tmp/http_test <dir>
#include "local_http_server.h"
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <unistd.h>
#include <cassert>
#include <cstdio>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

static std::string request(uint16_t port, const std::string &req) {
	int fd = socket(AF_INET, SOCK_STREAM, 0);
	sockaddr_in a{}; a.sin_family = AF_INET; a.sin_port = htons(port); a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	if (connect(fd, (sockaddr *)&a, sizeof a) != 0) return "CONNECT_FAIL";
	send(fd, req.data(), req.size(), 0);
	shutdown(fd, SHUT_WR);
	std::string out; char buf[4096]; ssize_t n;
	while ((n = recv(fd, buf, sizeof buf, 0)) > 0) out.append(buf, n);
	close(fd);
	return out;
}

int main(int argc, char **argv) {
	eagler::LocalHttpServer srv;
	eagler::LocalHttpServer::Config cfg;
	cfg.root_dir = argc > 1 ? argv[1] : ".";
	cfg.worker_threads = 4;
	std::string err;
	if (!srv.start(cfg, &err)) { fprintf(stderr, "start failed: %s\n", err.c_str()); return 1; }
	printf("listening on %s with %u workers\n", srv.base_url().c_str(), srv.worker_count());
	uint16_t p = srv.port();

	std::string r = request(p, "GET / HTTP/1.1\r\nHost: x\r\n\r\n");
	assert(r.rfind("HTTP/1.1 200 OK", 0) == 0 && r.find("text/html") != std::string::npos);
	r = request(p, "GET /../../etc/passwd HTTP/1.1\r\nHost: x\r\n\r\n");
	assert(r.find("root:") == std::string::npos); // traversal blocked
	r = request(p, "GET /index.html HTTP/1.1\r\nHost: x\r\nRange: bytes=0-4\r\n\r\n");
	assert(r.rfind("HTTP/1.1 206", 0) == 0 && r.find("Content-Length: 5") != std::string::npos);
	r = request(p, "GET /missing.wasm HTTP/1.1\r\nHost: x\r\n\r\n");
	assert(r.rfind("HTTP/1.1 404", 0) == 0);
	r = request(p, "POST / HTTP/1.1\r\nHost: x\r\n\r\n");
	assert(r.rfind("HTTP/1.1 405", 0) == 0);

	// Concurrency: 32 threads x 20 requests.
	std::vector<std::thread> ts; int fails = 0;
	for (int i = 0; i < 32; ++i) ts.emplace_back([&] {
		for (int j = 0; j < 20; ++j) {
			std::string rr = request(p, "GET /index.html HTTP/1.1\r\nHost: x\r\n\r\n");
			if (rr.rfind("HTTP/1.1 200", 0) != 0) __atomic_fetch_add(&fails, 1, __ATOMIC_RELAXED);
		}
	});
	for (auto &t : ts) t.join();
	printf("concurrent failures: %d, served: %llu, bytes: %llu\n", fails,
			(unsigned long long)srv.requests_served(), (unsigned long long)srv.bytes_sent());
	assert(fails == 0);
	srv.stop();
	puts("ALL TESTS PASSED");
	return 0;
}
