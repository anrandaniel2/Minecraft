// SPDX-License-Identifier: MIT

#include "bundle_unpacker.h"

#include <brotli/decode.h>

#include <sys/stat.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <mutex>
#include <sstream>
#include <thread>

namespace eagler {

namespace {

struct Payload {
	const char *id; // DOM id of the <script> element.
	const char *file; // Output filename.
	bool brotli; // Payload is brotli-compressed.
};

// Order matters only for logging; all are processed in parallel.
const Payload kPayloads[] = {
	{ "eag-inline-wasm-br", "classes.wasm", true },
	{ "eag-inline-server-wasm-br", "server-worker.wasm", true },
	{ "eag-inline-sounds", "sounds.epk", false },
	{ "eag-inline-assets", "assets.epk", false },
	{ "eag-inline-mesh-wasm-br", "mesh-worker.wasm", true },
};

bool read_file(const std::string &path, std::string &out) {
	std::ifstream f(path, std::ios::binary);
	if (!f) {
		return false;
	}
	f.seekg(0, std::ios::end);
	std::streamoff n = f.tellg();
	f.seekg(0, std::ios::beg);
	out.resize(static_cast<size_t>(n));
	f.read(&out[0], n);
	return static_cast<bool>(f);
}

bool write_file(const std::string &path, const void *data, size_t len) {
	std::string tmp = path + ".part";
	{
		std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
		if (!f) {
			return false;
		}
		f.write(static_cast<const char *>(data), static_cast<std::streamsize>(len));
		if (!f) {
			return false;
		}
	}
	return std::rename(tmp.c_str(), path.c_str()) == 0;
}

void mkdirs(const std::string &path) {
	std::string cur;
	for (size_t i = 0; i < path.size(); ++i) {
		cur.push_back(path[i]);
		if (path[i] == '/' && cur.size() > 1) {
			::mkdir(cur.c_str(), 0755);
		}
	}
	::mkdir(path.c_str(), 0755);
}

// Locates <script ... id="ID" ...>BODY</script>; returns [body_begin, body_end)
// and the [tag_begin, tag_end) of the whole element.
bool find_script(const std::string &html, const char *id, size_t &tag_begin, size_t &tag_end,
		size_t &body_begin, size_t &body_end) {
	std::string needle = std::string("id=\"") + id + "\"";
	size_t p = html.find(needle);
	if (p == std::string::npos) {
		return false;
	}
	tag_begin = html.rfind("<script", p);
	if (tag_begin == std::string::npos) {
		return false;
	}
	body_begin = html.find('>', p);
	if (body_begin == std::string::npos) {
		return false;
	}
	body_begin += 1;
	body_end = html.find("</script>", body_begin);
	if (body_end == std::string::npos) {
		return false;
	}
	tag_end = body_end + 9;
	return true;
}

} // namespace

// ---------------------------------------------------------------------------
// base64 (branch-light table decode, tolerant of \n / \r / spaces / '=')
// ---------------------------------------------------------------------------

bool BundleUnpacker::base64_decode(const char *in, size_t len, std::vector<uint8_t> &out) {
	static int8_t table[256];
	static std::once_flag once;
	std::call_once(once, [] {
		std::fill(std::begin(table), std::end(table), int8_t(-1));
		const char *alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
		for (int i = 0; i < 64; ++i) {
			table[static_cast<uint8_t>(alphabet[i])] = static_cast<int8_t>(i);
		}
		table[static_cast<uint8_t>('-')] = 62; // url-safe variants
		table[static_cast<uint8_t>('_')] = 63;
		table[static_cast<uint8_t>(' ')] = -2; // skip
		table[static_cast<uint8_t>('\n')] = -2;
		table[static_cast<uint8_t>('\r')] = -2;
		table[static_cast<uint8_t>('\t')] = -2;
		table[static_cast<uint8_t>('=')] = -3; // pad
	});

	out.clear();
	out.reserve(len / 4 * 3 + 3);
	uint32_t acc = 0;
	int bits = 0;
	for (size_t i = 0; i < len; ++i) {
		int8_t v = table[static_cast<uint8_t>(in[i])];
		if (v == -2) {
			continue;
		}
		if (v == -3) {
			break; // padding => end of data
		}
		if (v < 0) {
			return false;
		}
		acc = (acc << 6) | static_cast<uint32_t>(v);
		bits += 6;
		if (bits >= 8) {
			bits -= 8;
			out.push_back(static_cast<uint8_t>((acc >> bits) & 0xFF));
		}
	}
	return true;
}

// ---------------------------------------------------------------------------
// brotli
// ---------------------------------------------------------------------------

bool BundleUnpacker::brotli_decompress(const std::vector<uint8_t> &in, std::vector<uint8_t> &out) {
	BrotliDecoderState *st = BrotliDecoderCreateInstance(nullptr, nullptr, nullptr);
	if (!st) {
		return false;
	}
	BrotliDecoderSetParameter(st, BROTLI_DECODER_PARAM_LARGE_WINDOW, 1u);

	// Grow the output in large steps; typical ratio here is ~6-7x.
	out.clear();
	out.resize(std::max<size_t>(in.size() * 7, 1u << 20));

	size_t avail_in = in.size();
	const uint8_t *next_in = in.data();
	size_t total_out = 0;
	BrotliDecoderResult r;
	do {
		if (total_out == out.size()) {
			out.resize(out.size() + out.size() / 2);
		}
		size_t avail_out = out.size() - total_out;
		uint8_t *next_out = out.data() + total_out;
		r = BrotliDecoderDecompressStream(st, &avail_in, &next_in, &avail_out, &next_out, nullptr);
		total_out = out.size() - avail_out;
	} while (r == BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT);

	BrotliDecoderDestroyInstance(st);
	if (r != BROTLI_DECODER_RESULT_SUCCESS) {
		return false;
	}
	out.resize(total_out);
	return true;
}

// ---------------------------------------------------------------------------

bool BundleUnpacker::is_single_file_bundle(const std::string &html_path) {
	std::ifstream f(html_path, std::ios::binary);
	if (!f) {
		return false;
	}
	std::string head(1 << 16, '\0');
	f.read(&head[0], static_cast<std::streamsize>(head.size()));
	head.resize(static_cast<size_t>(f.gcount()));
	return head.find("id=\"eag-inline-") != std::string::npos;
}

bool BundleUnpacker::unpack(const Options &opts, UnpackStats *stats, std::string *error) {
	auto t0 = std::chrono::steady_clock::now();
	auto log = [&](const std::string &m) {
		if (opts.log) {
			opts.log(m);
		}
	};

	std::string html;
	if (!read_file(opts.html_path, html)) {
		if (error) {
			*error = "cannot read " + opts.html_path;
		}
		return false;
	}
	mkdirs(opts.out_dir);

	// Locate every payload up-front so the rewrite below can drop them.
	struct Span {
		const Payload *p;
		size_t tag_begin, tag_end, body_begin, body_end;
	};
	std::vector<Span> spans;
	for (const Payload &p : kPayloads) {
		Span s{ &p, 0, 0, 0, 0 };
		if (!find_script(html, p.id, s.tag_begin, s.tag_end, s.body_begin, s.body_end)) {
			if (error) {
				*error = std::string("payload not found: ") + p.id;
			}
			return false;
		}
		spans.push_back(s);
	}
	Span decoder{ nullptr, 0, 0, 0, 0 };
	bool has_decoder = find_script(html, "eag-inline-decoder", decoder.tag_begin, decoder.tag_end,
			decoder.body_begin, decoder.body_end);

	// -- Parallel decode ---------------------------------------------------
	unsigned n = opts.threads ? opts.threads : std::thread::hardware_concurrency();
	n = std::max(1u, std::min<unsigned>(n, static_cast<unsigned>(spans.size())));

	std::atomic<size_t> next{ 0 };
	std::atomic<bool> ok{ true };
	std::mutex err_mutex;
	std::string first_error;
	std::atomic<uint64_t> b64_bytes{ 0 }, dec_bytes{ 0 }, raw_bytes{ 0 };

	auto worker = [&] {
		while (ok.load()) {
			size_t i = next.fetch_add(1);
			if (i >= spans.size()) {
				return;
			}
			const Span &s = spans[i];
			std::vector<uint8_t> decoded;
			if (!base64_decode(html.data() + s.body_begin, s.body_end - s.body_begin, decoded)) {
				std::lock_guard<std::mutex> l(err_mutex);
				first_error = std::string("base64 decode failed: ") + s.p->id;
				ok.store(false);
				return;
			}
			b64_bytes += s.body_end - s.body_begin;
			dec_bytes += decoded.size();

			std::vector<uint8_t> raw;
			const std::vector<uint8_t> *to_write = &decoded;
			if (s.p->brotli) {
				if (!brotli_decompress(decoded, raw)) {
					std::lock_guard<std::mutex> l(err_mutex);
					first_error = std::string("brotli decode failed: ") + s.p->id;
					ok.store(false);
					return;
				}
				std::vector<uint8_t>().swap(decoded); // free early
				to_write = &raw;
			}
			raw_bytes += to_write->size();

			std::string out_path = opts.out_dir + "/" + s.p->file;
			if (!write_file(out_path, to_write->data(), to_write->size())) {
				std::lock_guard<std::mutex> l(err_mutex);
				first_error = "cannot write " + out_path;
				ok.store(false);
				return;
			}
			log(std::string("unpacked ") + s.p->file + " (" + std::to_string(to_write->size() / 1024 / 1024) + " MiB)");
		}
	};
	std::vector<std::thread> pool;
	for (unsigned t = 0; t < n; ++t) {
		pool.emplace_back(worker);
	}
	for (std::thread &t : pool) {
		t.join();
	}
	if (!ok.load()) {
		if (error) {
			*error = first_error;
		}
		return false;
	}

	// -- Rewrite the HTML ----------------------------------------------------
	// Remove payload elements (largest spans first so offsets stay valid).
	std::vector<std::pair<size_t, size_t>> cuts;
	for (const Span &s : spans) {
		cuts.emplace_back(s.tag_begin, s.tag_end);
	}
	if (has_decoder) {
		cuts.emplace_back(decoder.tag_begin, decoder.tag_end);
	}
	std::sort(cuts.begin(), cuts.end(), [](auto &a, auto &b) { return a.first > b.first; });
	for (auto &c : cuts) {
		html.erase(c.first, c.second - c.first);
	}

	// Neutralise the JS-side inline loader: the decoder init would throw
	// because its <script> is gone, so short-circuit the whole block by
	// making decodePayload a no-op path. The simplest robust approach: replace
	// the fetch shim's entry condition so every URL falls through to the real
	// fetch(). We do that by turning the payload map into an empty object and
	// disabling the decoder bootstrap.
	auto replace_all = [&](const std::string &from, const std::string &to) {
		size_t pos = 0;
		while ((pos = html.find(from, pos)) != std::string::npos) {
			html.replace(pos, from.size(), to);
			pos += to.size();
		}
	};
	// 1) Decoder bootstrap -> skipped.
	replace_all("var decoderBytes = decodePayload(\"eag-inline-decoder\");",
			"var decoderBytes = null; /* native unpack: decoder not needed */");
	replace_all("window.__eagBrotli.initSync({ module: decoderBytes });", "/* native unpack */");
	// 2) Asset URLs keep pointing at real files.
	replace_all("entries[i].url = inlinePayloadPrefix + name;", "/* native unpack: keep real URL */");
	// 3) WASM fetches fall through to the network (loopback server).
	replace_all("if (clean === \"mesh-worker.wasm\") {", "if (false && clean === \"mesh-worker.wasm\") {");
	replace_all("if (clean === \"server-worker.wasm\") {", "if (false && clean === \"server-worker.wasm\") {");
	replace_all("if (clean !== \"classes.wasm\") return originalFetch(input, init);",
			"return originalFetch(input, init); /* native unpack */");

	// 3b) The server-worker bootstrap wraps XMLHttpRequest with a shim meant
	//     for the inline assets.epk payload. Once the payload node is gone the
	//     shim delegates to a real XHR but never mirrors status/response/on*
	//     handlers back to the wrapper, so the worker's EPK download reports
	//     "Could not download EPK file". Leave the native XHR untouched.
	replace_all("self.XMLHttpRequest = function () {", "self.__eagInlineXHRUnused = function () {");
	replace_all("var OriginalXHR = self.XMLHttpRequest;", "var OriginalXHR = self.XMLHttpRequest; /* native unpack: shim disabled */");

	// 4) Multithreaded mode: the page is now served from a real http origin
	//    with COOP/COEP, so mesh + server workers can run.
	if (opts.enable_workers) {
		replace_all("singleThreadMode: true,", "singleThreadMode: false,");
	}

	// 5) Host diagnostics bridge: the page already keeps a structured boot log
	//    (window.__log) and a crash journal; mirror stage changes, boot
	//    percentages, console errors and uncaught errors to the native host
	//    via the loopback control endpoint so they show up in logcat.
	replace_all("window.__eaglerBoot = function (pct, text) {",
			"window.__eaglerBoot = function (pct, text) {\n"
			"\t\t\ttry { window.__eaglerHostLog && window.__eaglerHostLog(\"boot \" + pct + \"% \" + text); } catch (e) {}");
	replace_all("\t\t\t\t\tstage: function (name) {",
			"\t\t\t\t\tstage: function (name) {\n"
			"\t\t\t\t\t\ttry { window.__eaglerHostLog && window.__eaglerHostLog(\"stage \" + name); } catch (e) {}");
	replace_all("\t\t\t\tfunction fatal(kind, error) {",
			"\t\t\t\tfunction fatal(kind, error) {\n"
			"\t\t\t\t\ttry { window.__eaglerHostLog && window.__eaglerHostLog(\"FATAL \" + kind + \": \" + (error && (error.stack || error.message || error))); } catch (e) {}");
	{
		// Install the bridge itself as the very first script in <head>.
		static const char kBridge[] =
				"\n<script>(function(){\n"
				"var q=[],busy=false;\n"
				"function flush(){if(busy||!q.length)return;busy=true;var m=q.shift();\n"
				"  var x=new XMLHttpRequest();x.open('GET','/__host/log?'+encodeURIComponent(m).slice(0,6000),true);\n"
				"  x.onloadend=function(){busy=false;flush();};try{x.send();}catch(e){busy=false;}}\n"
				"window.__eaglerHostLog=function(m){q.push(String(m));if(q.length>200)q.shift();flush();};\n"
				"window.addEventListener('error',function(ev){window.__eaglerHostLog('window.error '+(ev&&ev.message)+' @'+(ev&&ev.filename)+':'+(ev&&ev.lineno));});\n"
				"window.addEventListener('unhandledrejection',function(ev){var r=ev&&ev.reason;window.__eaglerHostLog('unhandledrejection '+(r&&(r.stack||r.message)||r));});\n"
				"var ce=console.error;console.error=function(){try{window.__eaglerHostLog('console.error '+Array.prototype.join.call(arguments,' '));}catch(e){}return ce.apply(console,arguments);};\n"
				"var cw=console.warn;console.warn=function(){try{window.__eaglerHostLog('console.warn '+Array.prototype.join.call(arguments,' '));}catch(e){}return cw.apply(console,arguments);};\n"
				"window.__eaglerHostDump=function(){try{var j=window.__eaglerCrashJournal&&window.__eaglerCrashJournal.snapshot();\n"
				"  var l=(window.__log||[]).slice(-40);window.__eaglerHostLog('DUMP stage='+(j&&j.stage)+' state='+(j&&j.state)+' err='+window.__err+' ready='+window.__eaglerGameReady+' loaded='+window.__loaded+' xoi='+self.crossOriginIsolated+' workers='+(typeof Worker)+'\\n'+l.join('\\n'));}catch(e){window.__eaglerHostLog('DUMP failed '+e);}};\n"
				"window.__eaglerHostLog('bridge ready ua='+navigator.userAgent+' cores='+navigator.hardwareConcurrency+' mem='+(navigator.deviceMemory||'?')+' secure='+self.isSecureContext+' xoi='+self.crossOriginIsolated+' sab='+(typeof SharedArrayBuffer)+' origin='+location.origin);\n"
				"try{fetch(location.href,{method:'HEAD',cache:'no-store'}).then(function(r){window.__eaglerHostLog('headers coop='+r.headers.get('cross-origin-opener-policy')+' coep='+r.headers.get('cross-origin-embedder-policy')+' corp='+r.headers.get('cross-origin-resource-policy'));});}catch(e){}\n"
				"})();</script>\n";
		size_t head_tag = html.find("<head>");
		if (head_tag != std::string::npos) {
			html.insert(head_tag + 6, kBridge);
		}
	}

	// 6) Marker so the host / tests can tell this is the unpacked variant.
	size_t head = html.find("<head>");
	if (head != std::string::npos) {
		html.insert(head + 6, "\n<meta name=\"eagler-native-unpack\" content=\"1\">\n");
	}

	std::string index_path = opts.out_dir + "/" + opts.index_name;
	if (!write_file(index_path, html.data(), html.size())) {
		if (error) {
			*error = "cannot write " + index_path;
		}
		return false;
	}

	if (stats) {
		stats->payloads = spans.size();
		stats->base64_bytes = b64_bytes.load();
		stats->decoded_bytes = dec_bytes.load();
		stats->decompressed_bytes = raw_bytes.load();
		stats->threads = n;
		stats->seconds = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
	}
	log("wrote " + index_path + " (" + std::to_string(html.size() / 1024) + " KiB)");
	return true;
}

} // namespace eagler
