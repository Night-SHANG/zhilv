"""独立回读原生创作流程产物，不在Python复制规则执行器。"""
import copy
import json
import pathlib
import sys
import unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools'))
from check_authoring_evidence import validate_authoring_result
from check_snapshot import ValidationError

class AuthoringEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.catalog=json.loads((ROOT/'fixtures/rules_catalog.json').read_text())
        self.expected=json.loads((ROOT/'fixtures/authoring_expected.json').read_text())
        self.data=copy.deepcopy(self.expected)
    def verify(self):
        return validate_authoring_result(json.dumps(self.data),self.catalog,self.expected)
    def test_complete_creation_flow(self):
        self.assertEqual(self.verify()['tick'],6)
    def test_definition_order_is_not_semantic(self):
        self.data['rules']['modules'].reverse()
        for m in self.data['rules']['modules']: m['nodes'].reverse()
        self.verify()
    def test_edited_rule_corruption(self):
        self.data['rules']['modules'][-1]['nodes'][-1]['config']['version']=2
        with self.assertRaises(ValidationError): self.verify()
    def test_lost_old_version(self):
        self.data['rules']['modules'].pop(4)
        with self.assertRaises(ValidationError): self.verify()
    def test_binding_accidentally_updates_all_objects(self):
        self.data['world']['entities']['instances'][0]['rules'][0]['version']=2
        with self.assertRaises(ValidationError): self.verify()
    def test_state_not_reset_by_binding(self):
        self.data['world']['entities']['instances'][1]['state']['water_units']=0
        with self.assertRaises(ValidationError): self.verify()
    def test_new_definition_not_actually_run(self):
        self.data['world']['entities']['instances'][3]['state']['light_on']=False
        with self.assertRaises(ValidationError): self.verify()
    def test_fractional_tick_rejected(self):
        self.data['tick']=6.0
        with self.assertRaises(ValidationError): self.verify()
    def test_wrong_tick_rejected(self):
        self.data['tick']=5
        with self.assertRaises(ValidationError): self.verify()
    def test_privilege_field_not_accepted(self):
        self.data['catalog']=self.catalog
        with self.assertRaises(ValidationError): self.verify()
    def test_duplicate_json_key_rejected(self):
        text=json.dumps(self.data).replace('"tick": 6','"tick": 6, "tick": 6')
        with self.assertRaises(ValidationError):validate_authoring_result(text,self.catalog,self.expected)
