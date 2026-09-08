"""Update the arena perimeter to 2400 x 1350 and remove its obsolete divider.

Only arena markers, perimeter brushes/slabs and decorative rocks move. Terrain,
player starts, lighting and unrelated entities retain their authored coordinates.

Run: python scripts/update-arena-map.py
The updated source is also written to the issue-fixes overlay. This does not
compile or deploy a map; existing VPKs must be rebuilt separately.
"""
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
from vendor import datamodel as dmx

MAP = Path("content/dota_addons/dota2_rpg/maps/dota2_rpg_demo.vmap")


def remove_middle_brush(model):
    pending = [model.root["world"]]
    seen = set()
    gates = []
    while pending:
        parent = pending.pop()
        if parent.id in seen:
            continue
        seen.add(parent.id)
        children = parent.get("children", [])
        for child in children:
            if child is None:
                continue
            if child.get("entity_properties", {}).get("targetname") == "rpg_mid_gate_nav":
                gates.append((children, child))
            else:
                pending.append(child)
    if len(gates) > 1:
        raise ValueError("Expected at most one rpg_mid_gate_nav")
    for children, gate in gates:
        if gate["entity_properties"].get("classname") != "func_brush":
            raise ValueError("Refusing to remove a non-brush rpg_mid_gate_nav")
        # The serializer emits only reachable elements, dropping this brush's
        # private mesh data without changing terrain, perimeter, or asset refs.
        children.remove(gate)
    return bool(gates)


HALF_HEIGHT = 675
NONAV = 'materials/tools/nonavclip.vmat'


def set_arena_height(model, half_height=HALF_HEIGHT):
    """Set absolute dimensions, preserving wall thickness and unrelated map data.

    Brush child transforms are in map space. The Y radius of their source box
    is 512, so only the east/west mesh Y scale needs to change. Absolute target
    values make this safe to rerun after the first expansion.
    """
    changed = False

    def set_y(element, key, y):
        nonlocal changed
        vector = element[key]
        if vector[1] != y:
            element[key] = dmx.Vector3((vector[0], y, vector[2]))
            changed = True

    elements = list(model.elements)
    by_name = {e.get('entity_properties', {}).get('targetname'): e
               for e in elements if e.type == 'CMapEntity'}
    for side, sign in [('min', -1), ('max', 1)]:
        set_y(by_name['rpg_arena_' + side], 'origin', sign * half_height)
    for side, sign in [('north', 1), ('south', -1)]:
        wall = by_name['rpg_arena_wall_' + side]
        set_y(wall, 'origin', sign * (half_height + 16))
        set_y(wall['children'][0], 'origin', sign * (half_height + 16))
        for index in range(11):
            set_y(by_name[f'rpg_arena_rock_{side}_{index:02}'], 'origin',
                  sign * (half_height + 150))
    for side in ('east', 'west'):
        wall = by_name['rpg_arena_wall_' + side]
        set_y(wall['children'][0], 'scales', (half_height + 16) / 512)
        for index in range(3):
            set_y(by_name[f'rpg_arena_rock_{side}_{index:02}'], 'origin',
                  (index - 1) * half_height * .8)
    slabs = [e for e in elements if e.type == 'CMapMesh'
             and e['meshData']['materials'] == [NONAV]]
    if len(slabs) != 4:
        raise ValueError('Expected exactly four arena NONAV perimeter slabs')
    for slab in slabs:
        x, y, _ = slab['origin']
        if x == 0 and y != 0:
            set_y(slab, 'origin', (1 if y > 0 else -1) * (half_height + 16))
        elif abs(x) == 1200 and y == 0:
            set_y(slab, 'scales', (half_height + 16) / 512)
        else:
            raise ValueError('Unrecognized arena NONAV slab; inspect map before updating')
    return changed


def main():
    source = ROOT / MAP
    model = dmx.load(str(source))
    changed = remove_middle_brush(model)
    changed = set_arena_height(model) or changed
    data = model.echo("binary", 9) if changed else source.read_bytes()
    if changed:
        source.write_bytes(data)
    overlay = ROOT / "dota2_rpg_issue_fixes/overlay" / MAP
    overlay.write_bytes(data)
    print('Arena is 2400 x 1350 at Z=128; no static middle brush; overlay synced.'
          + (' Updated source.' if changed else ' Source already current.'))


if __name__ == "__main__":
    main()
