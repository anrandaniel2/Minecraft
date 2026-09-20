// SPDX-License-Identifier: MIT
//
// BundleUnpacker - converts the EaglerCraft *single-file* HTML build into a
// multi-file layout that the WebView can load efficiently.
//
// The single-file build embeds everything as base64 text inside
// <script type="application/octet-stream" id="eag-inline-..."> blocks:
//
//     eag-inline-decoder          brotli decoder (wasm)   (not needed here)
//     eag-inline-wasm-br          classes.wasm       (brotli)
//     eag-inline-mesh-wasm-br     mesh-worker.wasm   (brotli)
//     eag-inline-server-wasm-br   server-worker.wasm (brotli)
//     eag-inline-assets           assets.epk
//     eag-inline-sounds           sounds.epk
//
// At page load, JavaScript then has to atob() ~75 MB of text and brotli-
// decompress ~160 MB of WebAssembly, single-threaded on the main thread,
// *every launch*. This class does that work once, natively, on a thread pool,
// and writes plain files next to a rewritten, slim index.html whose loader
// fetches them over HTTP. That lets Chromium stream-compile the WASM and cache
// the compiled code between launches.
//
// No Godot dependencies: plain C++17 + brotli decoder, testable on the host.

#pragma once

#include <cstddef>
#include <cstdint>
#include <functional>
#include <string>
#include <vector>

namespace eagler {

struct UnpackStats {
	size_t payloads = 0;
	uint64_t base64_bytes = 0;
	uint64_t decoded_bytes = 0;
	uint64_t decompressed_bytes = 0;
	double seconds = 0.0;
	unsigned threads = 0;
};

class BundleUnpacker {
public:
	struct Options {
		std::string html_path; // Source single-file HTML.
		std::string out_dir; // Destination directory (created).
		std::string index_name = "index.html"; // Rewritten loader.
		unsigned threads = 0; // 0 = hardware concurrency.
		bool enable_workers = true; // Flip singleThreadMode -> false.
		bool strip_unused_loader = true; // Drop the JS-side decoder block.
		std::function<void(const std::string &)> log; // Optional.
	};

	// Returns true on success. On failure *error is set.
	static bool unpack(const Options &opts, UnpackStats *stats, std::string *error);

	// True if the file looks like a single-file build we know how to unpack.
	static bool is_single_file_bundle(const std::string &html_path);

	// Exposed for tests -------------------------------------------------
	// Decodes base64 (whitespace tolerant). Returns false on bad input.
	static bool base64_decode(const char *in, size_t len, std::vector<uint8_t> &out);
	// Brotli-decompresses a whole buffer. Returns false on error.
	static bool brotli_decompress(const std::vector<uint8_t> &in, std::vector<uint8_t> &out);
};

} // namespace eagler
