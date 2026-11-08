"""世界信封的独立回读；不能替代 Godot 运行测试。"""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import unittest
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))

class WorldContractTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads((ROOT/'fixtures/world_checkpoint.json').read_text())
        self.catalog = json.loads((ROOT/'fixtures/catalog.json').read_text())

    def validator(self):
        path = ROOT/'tools/check_world.py'
        self.assertTrue(path.exists(), '世界协议校验尚未实现')
        spec = importlib.util.spec_from_file_location('check_world', path)
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        return m.validate_world

    def valid(self, data=None):
        return self.validator()(json.dumps(self.data if data is None else data), self.catalog)

    def rejected(self, data):
        validate = self.validator()
        with self.assertRaises(ValueError):
            validate(json.dumps(data), self.catalog)

    def test_valid_roundtrip(self):
        self.assertEqual(self.valid(), self.data)
    def test_unknown_format(self):
        self.data['format']='rw.world/999';self.rejected(self.data)
    def test_unknown_field(self):
        self.data['script']='run()';self.rejected(self.data)
    def test_duplicate_terrain(self):
        self.data['terrain'].append(copy.deepcopy(self.data['terrain'][0]));self.rejected(self.data)
    def test_unknown_terrain_material(self):
        self.data['terrain'][0]['material_id']='core:missing';self.rejected(self.data)
    def test_instance_material_is_not_static_tile(self):
        self.data['terrain'][0]['material_id']='user:reservoir';self.rejected(self.data)
    def test_instance_inside_terrain(self):
        self.data['terrain'][0]['cell']=[3,2];self.rejected(self.data)
    def test_actor_feet_inside_terrain(self):
        self.data['terrain'][0]['cell']=[0,2];self.rejected(self.data)
    def test_actor_head_inside_terrain(self):
        self.data['terrain'][0]['cell']=[0,1];self.rejected(self.data)
    def test_actor_inside_instance(self):
        self.data['actor']['cell']=[3,2];self.rejected(self.data)
    def test_unknown_inventory_owner(self):
        self.data['actor']['id']='player:someone_else';self.rejected(self.data)
    def test_negative_coordinates(self):
        self.data['terrain'][0]['cell']=[-32,-1];self.assertEqual(self.valid(),self.data)
    def test_fractional_coordinate_rejected(self):
        self.data['terrain'][0]['cell']=[1.0,3];self.rejected(self.data)
    def test_boolean_coordinate_rejected(self):
        self.data['actor']['cell']=[True,2];self.rejected(self.data)
    def test_head_must_stay_in_coordinate_range(self):
        self.data['actor']['cell']=[0,-1000000];self.rejected(self.data)
    def test_duplicate_outer_key(self):
        raw=json.dumps(self.data).replace('"format": "rw.world/0.1"','"format": "rw.world/0.1", "format": "rw.world/0.1"')
        validate=self.validator()
        with self.assertRaises(ValueError): validate(raw,self.catalog)
    def test_missing_nested_dependency(self):
        self.data['entities']['instances'][0]['rules'][0]['version']=999;self.rejected(self.data)
    def test_budget_is_bounded(self):
        self.data['terrain']=[{'cell':[x,5],'material_id':'core:stone'} for x in range(16385)];self.rejected(self.data)
