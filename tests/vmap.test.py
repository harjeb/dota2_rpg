"""Offline Source 2 DMX-v9 contracts. Run: python tests/vmap.test.py.

Optional native provenance check: --native-map path/to/dota.vmap
The vendored MIT Blender Source Tools parser needs only Python's standard library.
These tests do not compile the map or validate model bounds/rendering in Dota.
"""
import argparse
import importlib.util
import io
import math
from pathlib import Path
import unittest

from vendor import datamodel as dmx

ROOT = Path(__file__).resolve().parents[1]
MAP = ROOT / 'content/dota_addons/dota2_rpg/maps/dota2_rpg_demo.vmap'
OVERLAY = ROOT / 'dota2_rpg_issue_fixes/overlay/content/dota_addons/dota2_rpg/maps/dota2_rpg_demo.vmap'
CLIP = 'materials/tools/toolsclip.vmat'
NONAV = 'materials/tools/nonavclip.vmat'
# Verified as prop_static models in lanpang/content/test2/maps/dota.vmap.
ROCK_MODELS = (
    'models/props_rock/riveredge_rock_wall003a.vmdl',
    'models/props_rock/riveredge_rock_wall002a.vmdl',
)
NATIVE_MAP = None
spec = importlib.util.spec_from_file_location('update_arena_map', ROOT / 'scripts/update-arena-map.py')
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


def reachable(root):
    seen = set()
    pending = [root]
    while pending:
        element = pending.pop()
        if element.id in seen:
            continue
        seen.add(element.id)
        yield element
        for value in element.values():
            if isinstance(value, dmx.Element):
                pending.append(value)
            elif isinstance(value, dmx._ElementArray):
                pending.extend(child for child in value if child is not None)


def signature(model):
    """Compare typed data and reference IDs, independent of serialization order."""
    def value_key(value):
        if isinstance(value, dmx.Element):
            return ('element', value.id)
        if isinstance(value, list):
            return (type(value).__name__, tuple(value_key(v) for v in value))
        return (type(value).__name__, value)

    def element_key(element):
        return (element.name, element.type, tuple((k, value_key(v)) for k, v in element.items()))

    return (model.format, model.format_ver, element_key(model.prefix_attributes),
            {e.id: element_key(e) for e in reachable(model.root)})


class VmapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model = dmx.load(str(MAP))
        cls.elements = list(reachable(cls.model.root))
        cls.entities = [e for e in cls.elements if e.type == 'CMapEntity']
        cls.meshes = [e for e in cls.elements if e.type == 'CMapMesh']

    def vector(self, actual, expected):
        self.assertEqual(len(actual), len(expected))
        for a, b in zip(actual, expected):
            self.assertTrue(math.isfinite(a))
            self.assertAlmostEqual(a, b, places=4)

    def named(self, name):
        matches = [e for e in self.entities if e['entity_properties'].get('targetname') == name]
        self.assertEqual(len(matches), 1, name)
        return matches[0]

    def mesh_contract(self, mesh, origin, scales, material, bounds):
        self.assertEqual(mesh.type, 'CMapMesh')
        self.vector(mesh['origin'], origin)
        self.vector(mesh['scales'], scales)
        self.vector(mesh['angles'], (0, 0, 0))
        self.assertFalse(mesh['editorOnly'])
        self.assertFalse(mesh['force_hidden'])
        self.assertEqual(mesh['physicsType'], 'default')
        data = mesh['meshData']
        self.assertEqual(data['materials'], [material])
        streams = data['faceData']['streams']
        indices = [s for s in streams if s['semanticName'] == 'materialindex']
        self.assertEqual(len(indices), 1)
        self.assertEqual(indices[0]['data'], [0] * 6)
        self.assertEqual(len(data['faceEdgeIndices']), 6)
        streams = data['vertexData']['streams']
        positions = [s for s in streams if s['semanticName'] == 'position']
        self.assertEqual(len(positions), 1)
        vertices = positions[0]['data']
        self.assertEqual(len(vertices), 8)
        # Hammer stores these mesh transforms in map space, including brush children.
        low = [min(v[i] * mesh['scales'][i] + mesh['origin'][i] for v in vertices) for i in range(3)]
        high = [max(v[i] * mesh['scales'][i] + mesh['origin'][i] for v in vertices) for i in range(3)]
        self.vector(low, bounds[0])
        self.vector(high, bounds[1])

    def brush(self, name, origin, scales, bounds):
        entity = self.named(name)
        props = entity['entity_properties']
        for key, expected in {'classname': 'func_brush', 'StartDisabled': '0',
                              'Solidity': '2', 'AlwaysSolidIgnoreNav': '0', 'solidbsp': '1'}.items():
            self.assertEqual(props[key], expected, (name, key))
        self.vector(entity['origin'], origin)
        self.vector(entity['angles'], (0, 0, 0))
        self.vector(entity['scales'], (1, 1, 1))
        self.assertFalse(entity['editorOnly'])
        self.assertFalse(entity['force_hidden'])
        self.assertEqual(len(entity['children']), 1)
        self.mesh_contract(entity['children'][0], origin, scales, CLIP, bounds)

    def test_binary_format_and_overlay(self):
        self.assertTrue(MAP.read_bytes().startswith(b'<!-- dmx encoding binary 9 format vmap 40 -->\n\0'))
        self.assertEqual((self.model.format, self.model.format_ver), ('vmap', 40))
        self.assertEqual(MAP.read_bytes(), OVERLAY.read_bytes())
        ids = [e['nodeID'] for e in self.elements if 'nodeID' in e]
        self.assertEqual(len(ids), len(set(ids)), 'Duplicate Hammer node IDs')
        self.assertEqual(len(self.elements), len({e.id for e in self.elements}))

    def test_flat_terrain(self):
        grids = [e for e in self.elements if e.type == 'CMapDotaTileGrid']
        self.assertEqual(len(grids), 1)
        self.vector(grids[0]['origin'], (-8192, -8192, 128))
        terrain = grids[0]['tileGridData']
        self.assertEqual((terrain['gridWidth'], terrain['gridHeight']), (64, 64))
        for key, size in {'cellsHidden': 4096, 'verticesHeight': 4225,
                          'verticesWater': 4225, 'objectConfiguration': 66049}.items():
            self.assertEqual(len(terrain[key]), size, key)
            self.assertFalse(any(terrain[key]), key)

    def test_arena_markers(self):
        for name, origin in {'min': (-1200, -450, 128), 'max': (1200, 450, 128),
                             'center': (0, 0, 128)}.items():
            marker = self.named('rpg_arena_' + name)
            self.assertEqual(marker['entity_properties']['classname'], 'info_target')
            self.vector(marker['origin'], origin)

    def test_invisible_colliding_perimeter(self):
        for side, y, low_y, high_y in [('north', 466, 450, 482), ('south', -466, -482, -450)]:
            self.brush('rpg_arena_wall_' + side, (0, y, 384), (1.59375, .03125, 2),
                       ((-1224, low_y, 128), (1224, high_y, 640)))
        for side, x, low_x, high_x in [('east', 1216, 1200, 1232), ('west', -1216, -1232, -1200)]:
            self.brush('rpg_arena_wall_' + side, (x, 0, 384), (1 / 48, .91015625, 2),
                       ((low_x, -466, 128), (high_x, 466, 640)))

    def test_no_static_middle_obstruction(self):
        for name in ('rpg_mid_gate_visual', 'rpg_mid_gate_nav'):
            self.assertFalse(any(e.get('entity_properties', {}).get('targetname') == name
                                 for e in self.model.elements), name)
        self.assertEqual(len(self.meshes), 8, 'Only four walls and four NONAV slabs')
        self.assertEqual(sum(e['entity_properties']['classname'] == 'func_brush' for e in self.entities), 4)
        # No authored collision may cross the playable middle corridor. Native
        # temporary trees own preparation navigation and are cut for battle.
        for mesh in self.meshes:
            streams = mesh['meshData']['vertexData']['streams']
            vertices = next(s['data'] for s in streams if s['semanticName'] == 'position')
            low = [min(v[i] * mesh['scales'][i] + mesh['origin'][i] for v in vertices) for i in range(2)]
            high = [max(v[i] * mesh['scales'][i] + mesh['origin'][i] for v in vertices) for i in range(2)]
            self.assertFalse(low[0] < 96 and high[0] > -96 and low[1] < 400 and high[1] > -400)

    def test_map_update_removes_only_legacy_brush_and_is_idempotent(self):
        model = dmx.load(in_file=io.BytesIO(MAP.read_bytes()))
        group = model.add_element('gate group', 'CMapGroup')
        group['children'] = dmx.make_array([], dmx.Element)
        model.root['world']['children'].append(group)
        before = signature(model)
        gate = model.add_element('legacy gate', 'CMapEntity')
        props = model.add_element('legacy gate properties', 'DmeElement')
        props['classname'] = 'func_brush'
        props['targetname'] = 'rpg_mid_gate_nav'
        props['Solidity'] = '2'
        props['AlwaysSolidIgnoreNav'] = '0'
        gate['entity_properties'] = props
        gate['children'] = dmx.make_array([model.add_element('legacy mesh', 'CMapMesh')], dmx.Element)
        group['children'].append(gate)
        self.assertTrue(updater.remove_middle_brush(model))
        self.assertEqual(signature(model), before, 'Unrelated typed data must remain unchanged')
        self.assertFalse(updater.remove_middle_brush(model))
        restored = dmx.load(in_file=io.BytesIO(model.echo('binary', 9)))
        self.assertEqual(signature(restored), before)
        self.assertFalse(any(e.get('entity_properties', {}).get('targetname') == 'rpg_mid_gate_nav'
                             for e in restored.elements))

    def test_four_nonav_slabs(self):
        slabs = [e for e in self.meshes if e['meshData']['materials'] == [NONAV]]
        self.assertEqual(len(slabs), 4)
        for y in (466, -466):
            matches = [e for e in slabs if tuple(e['origin']) == (0, y, 128)]
            self.assertEqual(len(matches), 1)
            self.mesh_contract(matches[0], (0, y, 128), (1.59375, .0625, .25), NONAV,
                               ((-1224, y - 32, 96), (1224, y + 32, 160)))
        for x in (1200, -1200):
            matches = [e for e in slabs if tuple(e['origin']) == (x, 0, 128)]
            self.assertEqual(len(matches), 1)
            self.mesh_contract(matches[0], (x, 0, 128), (1 / 24, .91015625, .25), NONAV,
                               ((x - 32, -466, 96), (x + 32, 466, 160)))

    def test_native_rock_perimeter(self):
        rocks = [e for e in self.entities if (e['entity_properties'].get('targetname') or '').startswith('rpg_arena_rock_')]
        self.assertEqual(len(rocks), 28)
        placements = []
        for side, y, yaw in [('north', 600, 90), ('south', -600, 270)]:
            placements.extend((side, i, (x, y, 128), yaw) for i, x in enumerate(range(-1200, 1201, 240)))
        for side, x, yaw in [('east', 1350, 0), ('west', -1350, 180)]:
            placements.extend((side, i, (x, y, 128), yaw) for i, y in enumerate(range(-360, 361, 360)))
        for side, index, origin, yaw in placements:
            prop = self.named(f'rpg_arena_rock_{side}_{index:02}')
            self.assertIn(prop, self.model.root['world']['children'])
            properties = prop['entity_properties']
            self.assertEqual(properties['classname'], 'prop_static')
            self.assertEqual(properties['model'], ROCK_MODELS[index % 2])
            self.assertEqual(properties['solid'], '0', 'Brushes, not model hulls, own collision')
            self.assertEqual(properties['renderamt'], '255')
            self.assertFalse(properties['materialoverride'])
            self.assertFalse(prop['editorOnly'])
            self.assertFalse(prop['force_hidden'])
            self.vector(prop['origin'], origin)
            self.vector(prop['angles'], (0, yaw, 0))
            self.vector(prop['scales'], (1, 1, 1))
        self.assertEqual(set(self.model.prefix_attributes['map_asset_references']), {CLIP, NONAV, *ROCK_MODELS})
        for mesh in self.meshes:
            self.assertTrue(set(mesh['meshData']['materials']) <= {CLIP, NONAV})

    def test_binary_round_trip_preserves_all_typed_data(self):
        before = signature(self.model)
        data = self.model.echo('binary', 9)
        restored = dmx.load(in_file=io.BytesIO(data))
        self.assertEqual(signature(restored), before)
        self.assertEqual(signature(self.model), before, 'Export must not mutate map data')
        prefix = restored.prefix_attributes
        self.assertEqual(prefix['asset_preview_thumbnail_format'], 'jpg')
        self.assertGreater(len(prefix['asset_preview_thumbnail']), 100)

    def test_parser_v9_unsigned_and_prefix_regression(self):
        model = dmx.DataModel('vmap', 40)
        model.add_element('test', 'CMapRootElement')
        model.prefix_attributes['text'] = 'inline prefix string'
        model.prefix_attributes['blob'] = dmx.Binary(b'\0\xff\x01')
        model.prefix_attributes['paths'] = dmx.make_array(['a.vmdl', '', 'b.vmat'], str)
        model.root['empty_string'] = ''
        model.root['empty_strings'] = dmx.make_array(['', 'model.vmdl', ''], str)
        model.root['null_element'] = None
        for kind, values in [(dmx.UInt8, [0, 255]), (dmx.UInt64, [0, 2 ** 64 - 1])]:
            model.root[kind.__name__] = kind(values[-1])
            model.root[kind.__name__ + '_array'] = dmx.make_array(values, kind)
        restored = dmx.load(in_file=io.BytesIO(model.echo('binary', 9)))
        self.assertEqual(signature(restored), signature(model))

    def test_native_source_model_provenance(self):
        if NATIVE_MAP is None:
            self.skipTest('Use --native-map to recheck external model provenance')
        native = dmx.load(str(NATIVE_MAP))
        models = {e['entity_properties'].get('model') for e in reachable(native.root)
                  if e.type == 'CMapEntity' and e.get('entity_properties', {}).get('classname') == 'prop_static'}
        self.assertTrue(set(ROCK_MODELS) <= models)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native-map', type=Path, help='Optional native dota.vmap to verify model provenance')
    args, remaining = parser.parse_known_args()
    NATIVE_MAP = args.native_map
    unittest.main(argv=[__file__, *remaining], verbosity=2)
