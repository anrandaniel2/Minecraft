// Host-side test: unpack the real single-file bundle and validate outputs.
//   g++ -std=c++17 -O2 -pthread -Isrc -Ithirdparty/brotli/c/include tests/bundle_unpacker_test.cpp \
//       src/bundle_unpacker.cpp thirdparty/brotli/c/dec/*.c thirdparty/brotli/c/common/*.c -o /tmp/unpack_test
//   /tmp/unpack_test web/eaglercraft.html /tmp/out
#include "bundle_unpacker.h"
#include <cassert>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

static std::vector<uint8_t> slurp(const std::string &p, size_t n = 8) {
	std::ifstream f(p, std::ios::binary); std::vector<uint8_t> b(n); f.read((char *)b.data(), n);
	b.resize((size_t)f.gcount()); return b;
}
static size_t fsize(const std::string &p) { std::ifstream f(p, std::ios::binary | std::ios::ate); return (size_t)f.tellg(); }

int main(int argc, char **argv) {
	// base64 unit checks
	std::vector<uint8_t> o;
	assert(eagler::BundleUnpacker::base64_decode("aGVs\nbG8=", 9, o) && o.size() == 5 && memcmp(o.data(), "hello", 5) == 0);
	assert(!eagler::BundleUnpacker::base64_decode("a!b", 3, o));
	if (argc < 3) { puts("unit ok (no bundle given)"); return 0; }

	eagler::BundleUnpacker::Options opt;
	opt.html_path = argv[1]; opt.out_dir = argv[2];
	opt.log = [](const std::string &m) { printf("  %s\n", m.c_str()); };
	eagler::UnpackStats st; std::string err;
	assert(eagler::BundleUnpacker::is_single_file_bundle(opt.html_path));
	if (!eagler::BundleUnpacker::unpack(opt, &st, &err)) { fprintf(stderr, "FAIL: %s\n", err.c_str()); return 1; }
	printf("payloads=%zu base64=%.1fMB decoded=%.1fMB raw=%.1fMB threads=%u time=%.2fs\n", st.payloads,
			st.base64_bytes / 1e6, st.decoded_bytes / 1e6, st.decompressed_bytes / 1e6, st.threads, st.seconds);

	std::string d = std::string(argv[2]) + "/";
	const uint8_t wasm[] = { 0, 'a', 's', 'm', 1, 0, 0, 0 };
	for (const char *w : { "classes.wasm", "mesh-worker.wasm", "server-worker.wasm" }) {
		auto h = slurp(d + w); assert(h.size() == 8 && memcmp(h.data(), wasm, 8) == 0);
	}
	for (const char *e : { "assets.epk", "sounds.epk" }) {
		auto h = slurp(d + e); assert(h.size() == 8 && memcmp(h.data(), "EAGPKG$$", 8) == 0);
	}
	std::ifstream idx(d + "index.html"); std::string html((std::istreambuf_iterator<char>(idx)), {});
	assert(html.find("id=\"eag-inline-wasm-br\"") == std::string::npos);
	assert(html.find("id=\"eag-inline-sounds\"") == std::string::npos);
	assert(html.find("eagler-native-unpack") != std::string::npos);
	assert(html.find("singleThreadMode: false") != std::string::npos);
	assert(!eagler::BundleUnpacker::is_single_file_bundle(d + "index.html"));
	printf("index.html = %zu KB (was %zu KB)\n", fsize(d + "index.html") / 1024, fsize(argv[1]) / 1024);
	puts("ALL TESTS PASSED");
	return 0;
}
