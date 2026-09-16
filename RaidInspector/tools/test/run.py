#!/usr/bin/env python3
"""Compile-check and exercise the real addon under Lua 5.1 - the dialect WoW
3.3.5a actually runs - without a game client.

    python tools/test/run.py            # compile every addon .lua, then run all *_test.lua
    python tools/test/run.py compile    # compile check only
    python tools/test/run.py test       # tests only

Requires `pip install lupa`. lupa's default runtime is a newer Lua that accepts
syntax the 3.3.5a client rejects, so the 5.1 runtime is selected explicitly.
Compiling under 5.1 also proves the 200-local / 60-upvalue limits hold.
"""
import glob
import os
import sys

try:
    from lupa import lua51
except ImportError:  # pragma: no cover
    sys.exit("lupa is required: pip install lupa")

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON_DIR = os.path.normpath(os.path.join(HERE, "..", ".."))

# Load order mirrors the .toc: data first, then the addon.
ADDON_FILES = ["RaidInspector_BiS.lua", "RaidInspector.lua"]


def compile_check():
    rc = 0
    for name in ADDON_FILES:
        path = os.path.join(ADDON_DIR, name)
        if not os.path.isfile(path):
            print("MISSING %s" % name)
            rc = 1
            continue
        L = lua51.LuaRuntime(unpack_returned_tuples=True)
        src = open(path, "r", encoding="utf-8").read()
        probe = L.eval(
            "function(src, name)"
            "  local c, e = loadstring(src, name)"
            "  if c then return true, '' end"
            "  return false, tostring(e)"
            "end"
        )
        ok, err = probe(src, "@" + name)
        if not ok:
            print("COMPILE FAIL %s\n  %s" % (name, err))
            rc = 1
        else:
            print("compiles clean (Lua 5.1): %s" % name)
    return rc


def run_tests():
    rc = 0
    tests = sorted(glob.glob(os.path.join(HERE, "*_test.lua")))
    if not tests:
        print("no *_test.lua found")
        return 1
    for test in tests:
        print("== %s" % os.path.basename(test), flush=True)
        L = lua51.LuaRuntime(unpack_returned_tuples=True)
        g = L.globals()
        g.STUB_PATH = os.path.join(HERE, "wowstub.lua")
        g.ADDON_DIR = ADDON_DIR
        g.ADDON_FILES = L.table(*ADDON_FILES)
        try:
            L.execute(open(test, "r", encoding="utf-8").read())
        except Exception as exc:  # lupa raises LuaError on os.exit(1) / runtime errors
            print("FAILED: %s" % exc)
            rc = 1
    return rc


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "all"
    rc = 0
    if mode in ("compile", "all"):
        rc |= compile_check()
    if mode in ("test", "all"):
        rc |= run_tests()
    sys.exit(rc)


if __name__ == "__main__":
    main()
