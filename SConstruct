#!/usr/bin/env python
# Build script for the EaglerHost GDExtension (C++ only).
#
#   scons platform=android target=template_release arch=arm64
#   scons platform=android target=template_debug   arch=arm64
#   scons platform=linux   target=template_debug            (editor-side stub)
#
# Requires ANDROID_HOME pointing at an SDK that has the NDK version expected by
# godot-cpp (see godot-cpp/tools/android.py, overridable via ndk_version=...).

import os

env = SConscript("godot-cpp/SConstruct")

env.Append(CPPPATH=["src/", "thirdparty/brotli/c/include"])
sources = Glob("src/*.cpp")

# Brotli decoder (C) - used by the native bundle unpacker.
brotli_env = env.Clone()
brotli_env.Append(CPPDEFINES=["BROTLI_BUILD_PORTABLE"])
sources += brotli_env.SharedObject(Glob("thirdparty/brotli/c/dec/*.c")) + brotli_env.SharedObject(Glob("thirdparty/brotli/c/common/*.c"))

# Threads + exceptions off (Godot style), position independent code.
if env["platform"] == "android":
    env.Append(LINKFLAGS=["-llog"])
    out_dir = "bin/android"
else:
    out_dir = "bin/" + env["platform"]

lib_name = "libeaglerhost{}{}".format(env["suffix"], env["SHLIBSUFFIX"])
library = env.SharedLibrary(os.path.join(out_dir, lib_name), source=sources)

Default(library)
