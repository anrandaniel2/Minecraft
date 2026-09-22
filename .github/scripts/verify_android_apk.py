#!/usr/bin/env python3
"""Verify that an Android APK is a real Godot/C# build containing actual game assets.

This exists because earlier CI runs released hand-made 2.4KB "placeholder" APKs
(text files named libgodot_android.so / godot-pck-placeholder.txt) whenever the
real Godot export failed. Any APK that fails these checks must never be
published.

Usage: verify_android_apk.py <path-to-apk>
"""
from __future__ import annotations

import hashlib
import os
import struct
import sys
import zipfile

MIN_APK_BYTES = 8 * 1024 * 1024        # real builds are 30-100 MB; placeholders are ~2 KB
MIN_ASSETS_TOTAL_BYTES = 4 * 1024 * 1024  # game data (textures, scenes, .NET assemblies)
MIN_LARGEST_ASSET_BYTES = 100 * 1024
MIN_ENGINE_SO_BYTES = 500 * 1024       # libgodot_android.so is many MB
MIN_DOTNET_SO_BYTES = 100 * 1024
MIN_CLASSES_DEX_BYTES = 2 * 1024
FORBIDDEN_ABI_PREFIXES = (
    "lib/armeabi-v7a/",
    "lib/x86/",
    "lib/x86_64/",
)
PLACEHOLDER_MARKERS = ("placeholder", "dummy", "example.so", "godot-pck-placeholder")
DOTNET_SO_HINTS = ("mono", "hostfxr", "coreclr", "hostpolicy", "systemio", "netcore")


def fail(errors: list[str]) -> None:
    print("\nAPK VERIFICATION FAILED:")
    for e in errors:
        print(f"  - {e}")
    sys.exit(1)


def main() -> None:
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(2)
    path = sys.argv[1]
    errors: list[str] = []

    if not os.path.isfile(path):
        fail([f"APK not found: {path}"])

    size = os.path.getsize(path)
    print(f"APK: {path}\nSize: {size} bytes ({size / 1e6:.1f} MB)")
    if size < MIN_APK_BYTES:
        errors.append(f"APK is only {size} bytes (< {MIN_APK_BYTES}) - this is a placeholder, not a real build")

    with open(path, "rb") as f:
        if f.read(2) != b"PK":
            errors.append("file is not a ZIP/APK archive")

    try:
        z = zipfile.ZipFile(path)
    except zipfile.BadZipFile as e:
        fail(errors + [f"cannot open APK as zip: {e}"])

    with z:
        infos = z.infolist()
        names = [i.filename for i in infos]
        print(f"Entries: {len(names)}")

        for n in names:
            low = n.lower()
            for marker in PLACEHOLDER_MARKERS:
                if marker in low:
                    errors.append(f"placeholder marker {marker!r} found in entry name: {n}")

        # AndroidManifest
        manifest = [i for i in infos if i.filename == "AndroidManifest.xml"]
        if not manifest:
            errors.append("AndroidManifest.xml missing")
        elif manifest[0].file_size < 400:
            errors.append(f"AndroidManifest.xml suspiciously small ({manifest[0].file_size} bytes)")

        # Real dex bytecode (not a 108-byte text stub)
        dex = [i for i in infos if i.filename.startswith("classes") and i.filename.endswith(".dex")]
        if not dex:
            errors.append("classes*.dex missing")
        else:
            biggest_dex = max(dex, key=lambda i: i.file_size)
            if biggest_dex.file_size < MIN_CLASSES_DEX_BYTES:
                errors.append(f"largest classes*.dex is only {biggest_dex.file_size} bytes")
            with z.open(biggest_dex) as df:
                if df.read(4) != b"dex\n":
                    errors.append(f"{biggest_dex.filename} does not start with DEX magic")

        # Native libs: arm64 only, real ELF binaries
        for prefix in FORBIDDEN_ABI_PREFIXES:
            bad = [n for n in names if n.startswith(prefix)]
            if bad:
                errors.append(f"forbidden ABI entries present ({prefix}): {bad[:5]}")

        arm64_sos = [i for i in infos if i.filename.startswith("lib/arm64-v8a/") and i.filename.endswith(".so")]
        if len(arm64_sos) < 2:
            errors.append(f"expected several lib/arm64-v8a/*.so entries (engine + .NET runtime), found {len(arm64_sos)}")
        engine_sos = [i for i in arm64_sos if "godot" in i.filename.lower()]
        if not engine_sos:
            errors.append("no lib/arm64-v8a/*godot*.so engine library found")
        elif max(i.file_size for i in engine_sos) < MIN_ENGINE_SO_BYTES:
            errors.append("engine .so is too small to be a real Godot binary")

        dotnet_sos = [i for i in arm64_sos if any(h in i.filename.lower() for h in DOTNET_SO_HINTS)]
        if not dotnet_sos:
            errors.append(
                "no .NET/Mono runtime .so found under lib/arm64-v8a/ "
                f"(entries: {[i.filename for i in arm64_sos][:10]}) - C# game would not run"
            )
        else:
            if max(i.file_size for i in dotnet_sos) < MIN_DOTNET_SO_BYTES:
                errors.append(".NET/Mono runtime .so is too small to be real")

        for so in arm64_sos:
            with z.open(so) as sf:
                if sf.read(4) != b"\x7fELF":
                    errors.append(f"{so.filename} is not a real ELF shared object")
        if len(arm64_sos) >= 2 and max(i.file_size for i in arm64_sos) < MIN_ENGINE_SO_BYTES:
            errors.append("largest native library is too small to be real")

        # Actual game assets (packed resources: textures, scenes, .NET assemblies)
        assets = [i for i in infos if i.filename.startswith("assets/") and not i.is_dir()]
        assets_total = sum(i.file_size for i in assets)
        print(f"assets/: {len(assets)} files, {assets_total / 1e6:.1f} MB total")
        if assets_total < MIN_ASSETS_TOTAL_BYTES:
            errors.append(f"assets/ only {assets_total} bytes total - real game data is missing")
        if not assets or max(i.file_size for i in assets) < MIN_LARGEST_ASSET_BYTES:
            errors.append("no large asset file (pck/assemblies) found under assets/")

        # Compiled C# must be shipped as managed assemblies - if raw game source
        # ends up in the APK the C# export plugin failed (e.g. solution not found)
        # and the game would not run.
        assemblies = [i for i in assets if i.filename.endswith(".dll")]
        if not assemblies:
            errors.append(
                "no managed .dll assemblies under assets/ (the C# game code is not embedded; "
                "dotnet publish output is missing)"
            )
        leaked_sources = [i for i in assets if i.filename.endswith(".cs") and i.file_size > 16]
        if leaked_sources:
            errors.append(
                f"{len(leaked_sources)} raw .cs source files were packed into assets/ instead of "
                f"compiled assemblies (e.g. {leaked_sources[0].filename}) - C# export plugin failed"
            )

        # Signed
        signed = [n for n in names if n.startswith("META-INF/") and n.endswith((".RSA", ".EC", ".DSA"))]
        if not signed:
            errors.append("APK is not signed (no META-INF/*.RSA|EC|DSA)")

        print("\nLargest entries:")
        for i in sorted(infos, key=lambda i: -i.file_size)[:15]:
            print(f"  {i.file_size:>12,}  {i.filename}")

    if errors:
        fail(errors)

    # ------------------------------------------------------------
    # Deep structure diagnostics (device-parse failure forensics):
    # CRC integrity, compression vs extractNativeLibs consistency,
    # zip alignment, APK Signing Block schemes, binary-AXML manifest
    # fields, and a SHA-256 for download verification.
    # ------------------------------------------------------------
    errors += deep_inspect(path)

    if errors:
        for e in errors:
            print(f"::error::{e}")
        print(f"\nFAILED: {len(errors)} issue(s) found:\n- " + "\n- ".join(errors))
        sys.exit(1)

    print("\nAPK VERIFICATION PASSED: real build with actual assets, arm64-v8a only.")


# ============================================================
# Deep APK structure diagnostics
# ============================================================

AXML_STRING = 0x0001
AXML_START_ELEMENT = 0x0102
TYPE_STRING = 0x03
TYPE_INT_DEC = 0x10
TYPE_INT_HEX = 0x11
TYPE_INT_BOOLEAN = 0x12
SIG_BLOCK_MAGIC = b"APK Sig Block 42"
SIG_SCHEME_IDS = {
    0x7109871A: "v2",
    0xF05368C0: "v3",
    0x1B93AD61: "v3.1",
    0x42726577: "v4(brek)",
}


def _decode_u8_len(data, off):
    """Android UTF-8 string length prefix (1-2 bytes). Returns (value, new_off)."""
    val = data[off]
    off += 1
    if val & 0x80:
        val = ((val & 0x7F) << 8) | data[off]
        off += 1
    return val, off


def _decode_u16_len(data, off):
    """Android UTF-16 string length prefix (2-4 bytes). Returns (value, new_off)."""
    val = struct.unpack_from("<H", data, off)[0]
    off += 2
    if val & 0x8000:
        val = ((val & 0x7FFF) << 16) | struct.unpack_from("<H", data, off)[0]
        off += 2
    return val, off


def parse_axml_manifest(data):
    """Minimal binary-XML decoder for AndroidManifest.xml.

    Returns {"elements": {tag: [ {attr: value}, ... ]}, "strings": [...]}
    where value is a (type, data) tuple decoded to a python value where easy.
    """
    if len(data) < 8 or struct.unpack_from("<HH", data, 0)[0] != 0x0003:
        raise ValueError("not binary AXML (bad magic)")
    strings = []
    elements = {}
    off = 8  # skip file header
    while off + 8 <= len(data):
        ctype, chsize, csize = struct.unpack_from("<HHI", data, off)
        if csize < 8 or off + csize > len(data):
            raise ValueError(f"bad AXML chunk at {off}")
        if ctype == AXML_STRING:
            count, style_count, flags, strings_start, _styles = struct.unpack_from(
                "<IIIII", data, off + 8
            )
            utf8 = bool(flags & 0x100)
            offsets = struct.unpack_from(f"<{count}I", data, off + 28)
            for so in offsets:
                p = off + strings_start + so
                if utf8:
                    _c, p = _decode_u8_len(data, p)
                    blen, p = _decode_u8_len(data, p)
                    strings.append(data[p : p + blen].decode("utf-8", "replace"))
                else:
                    clen, p = _decode_u16_len(data, p)
                    strings.append(data[p : p + clen * 2].decode("utf-16-le", "replace"))
        elif ctype == AXML_START_ELEMENT:
            # ResXMLTree_node (16B) + ResXMLTree_attrExt
            name_idx = struct.unpack_from("<I", data, off + 20)[0]
            attr_start, attr_size, attr_count = struct.unpack_from("<HHH", data, off + 24)
            tag = strings[name_idx] if name_idx < len(strings) else f"#{name_idx}"
            attrs = {}
            for i in range(attr_count):
                # ResXMLTree_attribute: ns u32, name u32, raw u32,
                # typed: u16 size, u8 res0, u8 dataType, u32 data
                a = off + 16 + attr_start + i * max(attr_size, 20)
                _ns = struct.unpack_from("<I", data, a)[0]
                an = struct.unpack_from("<I", data, a + 4)[0]
                raw = struct.unpack_from("<I", data, a + 8)[0]
                t_type = data[a + 15]
                t_data = struct.unpack_from("<I", data, a + 16)[0]
                name = strings[an] if an < len(strings) else f"#{an}"
                if t_type == TYPE_STRING:
                    idx = raw if raw != 0xFFFFFFFF else t_data
                    val = strings[idx] if idx < len(strings) else f"str#{idx}"
                elif t_type == TYPE_INT_BOOLEAN:
                    val = bool(t_data)
                elif t_type in (TYPE_INT_DEC, TYPE_INT_HEX):
                    val = t_data
                else:
                    val = (t_type, t_data)
                attrs[name] = val
            elements.setdefault(tag, []).append(attrs)
        off += csize
    return {"elements": elements, "strings": strings}


def parse_apk_signing_block(fdata, cd_offset):
    """Return list of (id, scheme_name) present in the APK Signing Block (or None)."""
    if cd_offset < 32:
        return None
    foot = fdata[cd_offset - 24 : cd_offset]
    block_size = struct.unpack_from("<Q", foot, 0)[0]
    if foot[8:] != SIG_BLOCK_MAGIC:
        return None  # no signing block (v1-only)
    start = cd_offset - block_size - 8
    if start < 0:
        return [("INVALID", "corrupt-sig-block")]
    ids = []
    p = start + 8  # skip the leading size field
    while p < cd_offset - 24:
        pair_len = struct.unpack_from("<Q", fdata, p)[0]
        if pair_len < 4 or p + 8 + pair_len > cd_offset - 24:
            ids.append(("INVALID", "corrupt-pair"))
            break
        sid = struct.unpack_from("<I", fdata, p + 8)[0]
        ids.append((sid, SIG_SCHEME_IDS.get(sid, "unknown")))
        p += 8 + pair_len
    return ids


def deep_inspect(apk):
    errors = []
    print("\n--- Deep structure diagnostics ---")

    # SHA-256 + size (for download-corruption detection on the user side)
    h = hashlib.sha256()
    with open(apk, "rb") as fsrc:
        for chunk in iter(lambda: fsrc.read(1 << 20), b""):
            h.update(chunk)
    sha = h.hexdigest()
    size = os.path.getsize(apk)
    print(f"[deep] sha256: {sha}")
    print(f"[deep] size:   {size} bytes")

    # ZIP integrity (CRC of every entry) — catches truncation/bit-rot
    try:
        with zipfile.ZipFile(apk) as zf:
            bad = zf.testzip()
            infos = zf.infolist()
            n_entries = len(infos)
            if bad:
                errors.append(f"CRC mismatch in entry {bad!r} (corrupt APK)")
                print(f"[deep] CRC: FAIL ({bad})")
            else:
                print(f"[deep] CRC: OK ({n_entries} entries)")

            # compression-method census
            import collections

            comp = collections.Counter()
            so_comp = collections.Counter()
            stored_info = []
            for i in infos:
                name = i.filename
                method = i.compress_type
                comp[method] += 1
                if method == 0:
                    stored_info.append(i)
                if name.startswith("lib/") and name.endswith(".so"):
                    so_comp["stored" if method == 0 else f"deflated({method})"] += 1
            print(f"[deep] compression methods (0=stored,8=deflate): {dict(comp)}")
            print(f"[deep] native .so compression: {dict(so_comp) or 'none'}")

            # alignment of stored entries (zipalign: 4B universal; 16B-page for
            # direct-mmaped libs on 16KB-page devices)
            mis4, mis16 = [], []
            with open(apk, "rb") as fraw:
                for i in stored_info:
                    # local header is 30 bytes + name + extra; data offset:
                    fraw.seek(i.header_offset)
                    lh = fraw.read(30)
                    if len(lh) < 30 or lh[:4] != b"PK\x03\x04":
                        errors.append(f"bad local header for {i.filename!r}")
                        continue
                    nlen, elen = struct.unpack("<HH", lh[26:30])
                    data_off = i.header_offset + 30 + nlen + elen
                    if data_off % 4 != 0:
                        mis4.append(i.filename)
                    if data_off % 16384 != 0:
                        if i.filename.endswith(".so") or i.filename == "resources.arsc":
                            mis16.append(i.filename)
            print(
                f"[deep] stored entries: {len(stored_info)}; "
                f"4B-misaligned: {len(mis4)}; 16KB-misaligned (.so/arsc): {len(mis16)}"
            )
            if mis4:
                errors.append(f"unzipalign'd stored entries (4B): {mis4[:5]}")

            # manifest facts (binary AXML)
            mf = None
            extract_libs = None
            try:
                manifest_data = zf.read("AndroidManifest.xml")
                mf = parse_axml_manifest(manifest_data)
                app = (mf["elements"].get("application") or [{}])[0]
                extract_libs = app.get("extractNativeLibs")
                m = (mf["elements"].get("manifest") or [{}])[0]
                us = (mf["elements"].get("uses-sdk") or [{}])[0]
                print(
                    "[deep] manifest: package=%s versionCode=%s versionName=%s "
                    "minSdk=%s targetSdk=%s extractNativeLibs=%s"
                    % (
                        m.get("package"),
                        m.get("versionCode"),
                        m.get("versionName"),
                        us.get("minSdkVersion"),
                        us.get("targetSdkVersion"),
                        extract_libs,
                    )
                )
                if not m.get("package"):
                    errors.append("manifest has no package attribute (parse would fail)")
                mn, tg = us.get("minSdkVersion"), us.get("targetSdkVersion")
                if isinstance(mn, int) and isinstance(tg, int) and mn > tg:
                    errors.append(f"minSdk {mn} > targetSdk {tg}")
            except Exception as e:  # noqa: BLE001
                errors.append(f"AndroidManifest.xml AXML decode failed: {e}")
                print(f"[deep] manifest decode: FAIL ({e})")

            # consistency rules that OEM installers reject
            if so_comp.get("stored") and extract_libs is False and mis16:
                errors.append(
                    "uncompressed .so with extractNativeLibs=false are not 16KB "
                    f"page-aligned: {mis16[:5]} (installs fail on 16KB-page devices)"
                )
            if any(k.startswith("deflated") for k in so_comp) and extract_libs is False:
                errors.append(
                    "deflated .so with extractNativeLibs=false (native lib extract "
                    "mismatch — INSTALL_PARSE_FAILED_INVALID_APK on many devices)"
                )
            if "resources.arsc" in zf.namelist():
                arsc = zf.getinfo("resources.arsc")
                if arsc.compress_type != 0:
                    errors.append("resources.arsc is compressed (must be stored)")

            v1 = any(
                n.startswith("META-INF/")
                and n.upper().endswith((".RSA", ".EC", ".DSA"))
                for n in zf.namelist()
            )
    except zipfile.BadZipFile as e:
        errors.append(f"zip structure unreadable (TRUNCATED/CORRUPT download?): {e}")
        print(f"[deep] zip open: FAIL ({e})")
        write_reports(apk, sha, size, None, errors)
        return errors

    # APK Signing Block (v2/v3) on the raw file
    with open(apk, "rb") as f:
        fdata = f.read()
    eocd = fdata.rfind(b"PK\x05\x06")
    if eocd < 0:
        errors.append("no EOCD — APK is truncated")
        print("[deep] EOCD: FAIL (not found — truncated file)")
        schemes = None
    else:
        cd_size, cd_off = struct.unpack_from("<II", fdata, eocd + 12)
        schemes = parse_apk_signing_block(fdata, cd_off)
        if schemes is None:
            print("[deep] signing block: none (v1-only APK)")
            if not v1:
                errors.append("no APK Signing Block and no v1 signature")
        else:
            names = [n for _i, n in schemes]
            print(f"[deep] signing block: schemes = {names}")
            if "v2" not in names and "v3" not in names and "v3.1" not in names:
                errors.append(f"signing block without v2/v3 scheme: {names}")

    write_reports(apk, sha, size, {"schemes": schemes, "manifest": mf}, errors)
    return errors


def write_reports(apk, sha, size, extra, errors):
    """Write builds/apk-report.md (release body) and the .sha256 file."""
    try:
        adir = os.path.dirname(os.path.abspath(apk))
        base = os.path.basename(apk)
        with open(os.path.join(adir, base + ".sha256"), "w") as f:
            f.write(f"{sha}  {base}\n")
        lines = [
            "## Minecraft Android build",
            "",
            f"- **File:** `{base}`",
            f"- **Size:** {size:,} bytes ({size / 1048576:.1f} MB)",
            f"- **SHA-256:** `{sha}`",
            "",
            "### Verify your download (parse/install failures are usually a truncated file)",
            "",
            "If your package installer says *\"Failure to parse package archive\"*, the file",
            "on your device is very likely truncated or corrupt (check device free storage —",
            "the game needs well over 200 MB free to install and run). Compare the file size",
            "and SHA-256 above with your copy:",
            "",
            "```",
            f"# on a PC (the sizes MUST match exactly: {size} bytes)",
            "sha256sum Minecraft-26.3-Android-arm64.apk",
            "# on the device (adb)",
            f"adb shell ls -l /sdcard/Download/Minecraft-26.3-Android-arm64.apk   # expect {size}",
            "adb install -r Minecraft-26.3-Android-arm64.apk",
            "```",
            "",
            "If the size or hash differs, re-download the file (ideally on a PC) and copy",
            "it to the device. If they match and installation still fails, please send the",
            "full `adb logcat` around the install (including the exception message above",
            "the `at ...` stack frames).",
        ]
        if extra and extra.get("schemes") is not None:
            lines += ["", f"Signature schemes: {sorted({n for _i, n in extra['schemes']})}"]
        if errors:
            lines += ["", "**Build-internal diagnostics FAILED:** " + "; ".join(errors)]
        with open(os.path.join(adir, "apk-report.md"), "w") as f:
            f.write("\n".join(lines) + "\n")
    except OSError as e:
        print(f"warn: could not write report: {e}")


if __name__ == "__main__":
    main()
