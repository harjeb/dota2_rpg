"""Remove the obsolete static divider from the binary VMAP, preserving other data.

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


def main():
    source = ROOT / MAP
    model = dmx.load(str(source))
    changed = remove_middle_brush(model)
    data = model.echo("binary", 9) if changed else source.read_bytes()
    if changed:
        source.write_bytes(data)
    overlay = ROOT / "dota2_rpg_issue_fixes/overlay" / MAP
    overlay.write_bytes(data)
    print("Removed static middle brush; overlay synced." if changed
          else "No static middle brush; overlay synced.")


if __name__ == "__main__":
    main()
