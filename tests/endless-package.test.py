"""Self-contained package checks; these are not a Dota compiler or engine test."""
from pathlib import Path
import hashlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
GAME = ROOT / 'game/dota_addons/dota2_rpg_endless'
CONTENT = ROOT / 'content/dota_addons/dota2_rpg_endless'
LUA = GAME / 'scripts/vscripts'
for path in LUA.rglob('*.lua'):
    for dep in re.findall(r'require\s*\(?\s*[\"\x27]([^\"\x27]+)', path.read_text(encoding='utf-8-sig')):
        assert (LUA / (dep.replace('.', '/') + '.lua')).exists(), (path, dep)
for path in (CONTENT / 'panorama/layout').rglob('*.xml'):
    for dep in re.findall(r'file://\{resources\}/([^\"]+)', path.read_text(encoding='utf-8-sig')):
        assert (CONTENT / 'panorama' / dep).exists(), (path, dep)
assert 'dota2_rpg_demo' in (GAME / 'addoninfo.txt').read_text(encoding='utf-8')
assert (CONTENT / 'maps/dota2_rpg_demo.vmap').exists()
assert 'CreateHTTPRequest' not in (LUA / 'battle/run_results.lua').read_text(encoding='utf-8')
assert 'arena_integration").Install(self)' not in '\n'.join(line for line in (LUA / 'addon_game_mode.lua').read_text(encoding='utf-8').splitlines() if not line.lstrip().startswith('--'))
normal = ROOT / 'game/dota_addons/dota2_rpg'
def hashes(root):
    return {p.relative_to(root).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file()}
before = hashes(normal)
with tempfile.TemporaryDirectory(prefix='endless_install_') as temp:
    target = Path(temp)
    (target / 'game/dota').mkdir(parents=True)
    result = subprocess.run(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(ROOT / 'scripts/install-endless-ui.ps1'), '-DotaPath', str(target)], cwd=ROOT, capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    installed = target / 'game/dota_addons/dota2_rpg_endless'
    for locale in ('addon_english.txt', 'addon_schinese.txt'):
        assert (installed / 'resource' / locale).read_bytes() == (GAME / 'resource' / locale).read_bytes()
    assert (installed / 'scripts/vscripts/endless/cards.lua').exists()
    assert (target / 'content/dota_addons/dota2_rpg_endless/maps/dota2_rpg_demo.vmap').exists()
    assert not (target / 'game/dota_addons/dota2_rpg').exists()
assert hashes(normal) == before, 'installer must not modify normal addon'
print('PASS self-contained Lua/XML dependencies, local results, battlefield, mock install and UI103 installed locale hashes; no engine compilation')
