// Mirrors AppUpdater::_compare_versions / _normalize_version semantics on
// plain std::string so it can run without the engine.
#include <cassert>
#include <cstdio>
#include <string>
#include <vector>

static std::string norm(std::string v) {
	if (!v.empty() && (v[0] == 'v' || v[0] == 'V')) v = v.substr(1);
	auto p = v.find('+'); if (p != std::string::npos) v.resize(p);
	return v;
}
static long seg(const std::string &s) { long n = 0; for (char c : s) { if (c < '0' || c > '9') break; n = n * 10 + (c - '0'); } return n; }
static int cmp(const std::string &A, const std::string &B) {
	auto split = [](const std::string &s, std::string &core, std::string &pre) { auto d = s.find('-'); core = s.substr(0, d); pre = d == std::string::npos ? "" : s.substr(d + 1); };
	std::string ca, pa, cb, pb; split(A, ca, pa); split(B, cb, pb);
	auto parts = [](const std::string &s) { std::vector<std::string> r; std::string c; for (char ch : s) { if (ch == '.') { r.push_back(c); c.clear(); } else c += ch; } r.push_back(c); return r; };
	auto xa = parts(ca), xb = parts(cb); size_t n = std::max(xa.size(), xb.size());
	for (size_t i = 0; i < n; ++i) { long a = i < xa.size() ? seg(xa[i]) : 0, b = i < xb.size() ? seg(xb[i]) : 0; if (a != b) return a < b ? -1 : 1; }
	if (pa.empty() != pb.empty()) return pa.empty() ? 1 : -1;
	return pa.compare(pb);
}
int main() {
	assert(cmp(norm("v26.2.7"), norm("26.2.6")) > 0);
	assert(cmp(norm("26.2.6.42"), norm("26.2.6")) > 0);
	assert(cmp(norm("26.2.6.42"), norm("26.2.6.41")) > 0);
	assert(cmp(norm("26.2.6"), norm("26.2.6")) == 0);
	assert(cmp(norm("26.2.6-beta"), norm("26.2.6")) < 0);
	assert(cmp(norm("26.10.0"), norm("26.9.9")) > 0);
	assert(cmp(norm("1.0.0+build5"), norm("1.0.0")) == 0);
	std::puts("version compare OK");
}
