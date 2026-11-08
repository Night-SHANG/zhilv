"""仅测试离线JSON契约；不证明Godot游戏行为。"""
import copy
import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from check_snapshot import validate, ValidationError
CAT = json.loads((ROOT / 'fixtures/catalog.json').read_text())
BASE = json.loads((ROOT / 'fixtures/checkpoint.json').read_text())

class SnapshotContractTests(unittest.TestCase):
    def setUp(self):
        self.d = copy.deepcopy(BASE)

    def reject(self):
        with self.assertRaises(ValidationError):
            validate(json.dumps(self.d), CAT)

    def test_valid_checkpoint(self):
        self.assertEqual(validate(json.dumps(self.d), CAT), self.d)

    def test_roundtrip_keeps_identity_rules_and_water(self):
        a = validate(json.dumps(self.d), CAT)
        b = validate(json.dumps(a), CAT)
        self.assertEqual(b, BASE)
        self.assertEqual(b['instances'][0]['state']['water_units'], 375)

    def test_same_material_keeps_two_distinct_instances(self):
        d = validate(json.dumps(self.d), CAT)
        self.assertEqual(len(d['instances']), 2)
        self.assertNotEqual(d['instances'][0]['rules'], d['instances'][1]['rules'])

    def test_location_only_change_keeps_program_and_state(self):
        before = copy.deepcopy(self.d['instances'][0])
        self.d['instances'][0]['location'] = {'kind':'inventory','owner':'player:local'}
        after = validate(json.dumps(self.d), CAT)['instances'][0]
        self.assertEqual(after['id'], before['id'])
        self.assertEqual(after['rules'], before['rules'])
        self.assertEqual(after['state'], before['state'])

    def test_duplicate_identity_rejected(self):
        self.d['instances'][1]['id'] = self.d['instances'][0]['id']; self.reject()

    def test_duplicate_world_cell_rejected(self):
        self.d['instances'][1]['location'] = self.d['instances'][0]['location']; self.reject()

    def test_world_and_inventory_location_cannot_coexist(self):
        self.d['instances'][0]['location']['owner'] = 'player:local'; self.reject()

    def test_missing_material_rejected(self):
        self.d['instances'][0]['material_id'] = 'missing:thing'; self.reject()

    def test_missing_rule_version_rejected(self):
        self.d['instances'][0]['rules'][0]['version'] = 99; self.reject()

    def test_missing_rule_rejected(self):
        self.d['instances'][0]['rules'][0]['id'] = 'missing:rule'; self.reject()

    def test_duplicate_rule_rejected(self):
        self.d['instances'][0]['rules'].append(self.d['instances'][0]['rules'][0]); self.reject()

    def test_stateful_material_cannot_be_count_only(self):
        self.d['stacks']['user:reservoir'] = 2; self.reject()

    def test_negative_stack_rejected(self):
        self.d['stacks']['core:stone'] = -1; self.reject()

    def test_boolean_stack_rejected(self):
        self.d['stacks']['core:stone'] = True; self.reject()

    def test_zero_stack_rejected(self):
        self.d['stacks']['core:stone'] = 0; self.reject()

    def test_water_over_capacity_rejected(self):
        self.d['instances'][0]['state']['water_units'] = 1001; self.reject()

    def test_negative_water_rejected(self):
        self.d['instances'][0]['state']['water_units'] = -1; self.reject()

    def test_bool_is_not_water_quantity(self):
        self.d['instances'][0]['state']['water_units'] = True; self.reject()

    def test_fractional_quantity_rejected(self):
        self.d['instances'][0]['state']['water_units'] = 0.1; self.reject()

    def test_nan_rejected(self):
        self.d['instances'][0]['state']['water_units'] = float('nan'); self.reject()

    def test_infinity_rejected(self):
        self.d['instances'][0]['state']['water_units'] = float('inf'); self.reject()

    def test_unknown_state_rejected(self):
        self.d['instances'][0]['state']['execute_script'] = 'script.gd'; self.reject()

    def test_unknown_root_rejected(self):
        self.d['plugin_path'] = '../../run.gd'; self.reject()

    def test_unknown_schema_rejected(self):
        self.d['format'] = 'rw.instances/999'; self.reject()

    def test_coordinate_strings_rejected(self):
        self.d['instances'][0]['location']['cell'] = ['a','b']; self.reject()

    def test_noninteger_coordinate_rejected(self):
        self.d['instances'][0]['location']['cell'] = [1.5,2]; self.reject()

    def test_negative_coordinates_supported(self):
        self.d['instances'][0]['location']['cell'] = [-5,-2]
        self.assertEqual(validate(json.dumps(self.d), CAT)['instances'][0]['location']['cell'],[-5,-2])

    def test_unsafe_identifier_rejected(self):
        self.d['instances'][0]['id'] = '../../thing'; self.reject()

    def test_duplicate_json_keys_rejected(self):
        raw = json.dumps(self.d).replace('"format": "rw.instances/0.1"', '"format":"rw.instances/0.1", "format":"rw.instances/0.1"')
        with self.assertRaises(ValidationError): validate(raw, CAT)

    def test_excessive_bytes_rejected(self):
        with self.assertRaises(ValidationError): validate(' ' * (1024*1024+1) + json.dumps(self.d), CAT)

    def test_excessive_instance_count_rejected(self):
        self.d['instances'] = [self.d['instances'][0]] * 4097; self.reject()

    def test_depth_limited(self):
        with self.assertRaises(ValidationError): validate('['*40+'0'+']'*40, CAT)

    def test_missing_state_field_rejected(self):
        del self.d['instances'][0]['state']['water_units']; self.reject()

    def test_int_not_boolean_light_flag(self):
        self.d['instances'][0]['state']['light_on'] = 1; self.reject()

    def test_oversized_integer_rejected(self):
        self.d['stacks']['core:stone'] = 10**100; self.reject()

if __name__ == '__main__': unittest.main()
