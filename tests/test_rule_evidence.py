"""独立检查原生验收工件；这里不解释或执行词条程序。"""
import copy
import json
import pathlib
import sys
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from check_rule_evidence import validate_fixture_result
from check_snapshot import ValidationError

class RuleEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.catalog = json.loads((ROOT/'fixtures/rules_catalog.json').read_text())
        self.world = json.loads((ROOT/'fixtures/rules_world.json').read_text())
        self.rules = json.loads((ROOT/'fixtures/rules_pack.json').read_text())
        result_world = copy.deepcopy(self.world)
        result_world['entities']['instances'][0]['state']['water_units'] = 300
        result_world['entities']['instances'][1]['state']['water_units'] = 200
        self.valid = {'format':'rw.simulation/0.1','tick':5,'world':result_world,'rules':copy.deepcopy(self.rules)}
    def verify(self, d):
        return validate_fixture_result(json.dumps(d), self.catalog, self.world, self.rules)
    def test_expected_native_result(self):
        self.assertEqual(self.verify(self.valid)['tick'],5)
    def test_rule_order_is_not_significant(self):
        self.valid['rules']['modules'].reverse()
        for m in self.valid['rules']['modules']: m['nodes'].reverse()
        self.assertEqual(self.verify(self.valid)['tick'],5)
    def test_missing_rules_rejected(self):
        del self.valid['rules']
        with self.assertRaises(ValidationError): self.verify(self.valid)
    def test_changed_program_rejected(self):
        self.valid['rules']['modules'][0]['nodes'][0]['op']='execute_script'
        with self.assertRaises(ValidationError): self.verify(self.valid)
    def test_water_creation_rejected(self):
        self.valid['world']['entities']['instances'][0]['state']['water_units']+=1
        with self.assertRaises(ValidationError): self.verify(self.valid)
    def test_water_disappearance_rejected(self):
        self.valid['world']['entities']['instances'][1]['state']['water_units']-=1
        with self.assertRaises(ValidationError): self.verify(self.valid)
    def test_fractional_water_rejected(self):
        self.valid['world']['entities']['instances'][0]['state']['water_units']=300.0
        with self.assertRaises(ValidationError): self.verify(self.valid)
    def test_wrong_tick_rejected(self):
        self.valid['tick']=4
        with self.assertRaises(ValidationError): self.verify(self.valid)
    def test_boolean_tick_rejected(self):
        self.valid['tick']=True
        with self.assertRaises(ValidationError): self.verify(self.valid)
    def test_dropped_instance_rejected(self):
        self.valid['world']['entities']['instances'].pop()
        with self.assertRaises(ValidationError): self.verify(self.valid)
    def test_moved_owner_rejected(self):
        self.valid['world']['entities']['instances'][3]['location']['owner']='player:other'
        with self.assertRaises(ValidationError): self.verify(self.valid)
    def test_rule_version_change_rejected(self):
        self.valid['rules']['modules'][0]['version']=2
        with self.assertRaises(ValidationError): self.verify(self.valid)
    def test_duplicate_json_fields_rejected(self):
        raw=json.dumps(self.valid).replace('"tick": 5','"tick": 5, "tick": 5')
        with self.assertRaises(ValidationError): validate_fixture_result(raw,self.catalog,self.world,self.rules)
