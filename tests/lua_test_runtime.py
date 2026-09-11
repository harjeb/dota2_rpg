"""Dependency-free Lua subprocess test helper. Missing runtime is a failure, not a skip."""
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]

def lua_literal(value):
    if value is None: return "nil"
    if isinstance(value, bool): return "true" if value else "false"
    if isinstance(value, (int, float)):
        if not math.isfinite(value): raise ValueError("Non-finite Lua fixture")
        return repr(value)
    if isinstance(value, str):
        out = []
        for char in value:
            n = ord(char)
            if char in ('\\', '"'): out.append('\\' + char)
            elif n < 32: out.append('\\%03d' % n)
            else: out.append(char)
        return '"' + ''.join(out) + '"'
    if isinstance(value, (list, tuple)):
        return '{' + ','.join(lua_literal(item) for item in value) + '}'
    if isinstance(value, dict):
        return '{' + ','.join('['+lua_literal(key)+']='+lua_literal(item) for key,item in value.items()) + '}'
    raise TypeError(type(value))

def interpreter():
    explicit = os.environ.get('LUA_BIN')
    if explicit:
        found = shutil.which(explicit)
        if not found: raise RuntimeError('LUA_BIN is not executable: ' + explicit)
        return found
    for name in ('lua', 'lua5.4', 'lua5.3', 'luajit', 'texlua'):
        found = shutil.which(name)
        if found: return found
    raise RuntimeError('Lua runtime required: install Lua 5.1+ / LuaJIT / texlua or set LUA_BIN; backend checks cannot be skipped')

def run_lua(source, timeout=40):
    prefix = 'package.path = ' + lua_literal(str(ROOT / 'game/dota_addons/dota2_rpg/scripts/vscripts/?.lua')) + ' .. ";" .. package.path\n'
    with tempfile.TemporaryDirectory(prefix='rpg_lua_test_') as directory:
        path = Path(directory) / 'test.lua'
        path.write_text(prefix+source, encoding='utf-8')
        result = subprocess.run([interpreter(), str(path)], cwd=ROOT, text=True, encoding='utf-8', capture_output=True, timeout=timeout)
    if result.returncode:
        raise AssertionError(result.stdout + result.stderr)
    return result.stdout
