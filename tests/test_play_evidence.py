"""独立原生操作存档检查器的失败输入；不另写模拟实现。"""
import copy
import importlib.util
import json
import pathlib
import sys
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from check_snapshot import ValidationError

class PlayEvidenceTests(unittest.TestCase):
 def setUp(self):
  self.catalog=json.loads((ROOT/'fixtures/catalog.json').read_text())
  self.definition={'id':'scenario:platform','version':1,'objectives':[{'id':'goal:walk','requires':[]}]}
  self.rules={'format':'rw.rules/0.1','modules':[{'id':'user:idle','version':1,'parameters':{},'nodes':[{'id':'yes','op':'bool','inputs':{},'config':{'value':True}}],'effects':[]}]}
  world=json.loads((ROOT/'fixtures/world_checkpoint.json').read_text());world['format']='rw.world/0.3';world['water']=[]
  for e in world['entities']['instances']: e['rules']=[]
  x,y=world['actor']['cell'];world['actor']['body_foot']=[x*1024+512,(y+1)*1024]
  self.data={'format':'rw.play/0.1','motion':{'velocity_x':0,'velocity_y':0},'expedition':{'format':'rw.expedition/0.1','scenario_id':'scenario:platform','scenario_version':1,'completed':[], 'simulation':{'format':'rw.simulation/0.2','tick':10,'clock':{'cycle_ticks':120,'daylight_ticks':60,'paused':True},'world':world,'rules':copy.deepcopy(self.rules)}}}
 def validate(self,text=None):
  path=ROOT/'tools/check_play_evidence.py'
  self.assertTrue(path.exists(),'independent play evidence validator has not been implemented')
  spec=importlib.util.spec_from_file_location('playcheck',path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
  return module.validate_play_checkpoint(json.dumps(self.data) if text is None else text,self.catalog,self.definition,self.rules)
 def test_valid_native_envelope(self):self.assertEqual(self.validate()['motion'],self.data['motion'])
 def test_motion_not_bool_fraction_or_unbounded(self):
  for value in [True,0.1,6145,-6145,'0',None]:
   with self.subTest(value=value):
    self.data['motion']['velocity_x']=value
    with self.assertRaises(ValidationError):self.validate()
 def test_actor_anchor_must_match_body(self):
  self.data['expedition']['simulation']['world']['actor']['body_foot'][0]+=1024
  with self.assertRaises(ValidationError):self.validate()
 def test_body_required(self):
  self.data['expedition']['simulation']['world']['format']='rw.world/0.2';self.data['expedition']['simulation']['world']['actor'].pop('body_foot')
  with self.assertRaises(ValidationError):self.validate()
 def test_clock_malformed(self):
  self.data['expedition']['simulation']['clock']['daylight_ticks']=121
  with self.assertRaises(ValidationError):self.validate()
 def test_unknown_goal_rejected(self):
  self.data['expedition']['completed']=['goal:missing']
  with self.assertRaises(ValidationError):self.validate()
 def test_goal_dependency_is_required(self):
  self.definition['objectives'].append({'id':'goal:second','requires':['goal:walk']})
  self.data['expedition']['completed']=['goal:second']
  with self.assertRaises(ValidationError):self.validate()
 def test_rule_content_must_match_expected(self):
  self.data['expedition']['simulation']['rules']['modules'][0]['nodes'][0]['config']['value']=False
  with self.assertRaises(ValidationError):self.validate()
 def test_bound_rule_must_be_in_checkpoint(self):
  self.data['expedition']['simulation']['world']['entities']['instances'][0]['rules']=[{'id':'user:nightlight','version':1}]
  with self.assertRaises(ValidationError):self.validate()
 def test_duplicate_keys_rejected(self):
  with self.assertRaises(ValidationError):self.validate('{"format":"rw.play/0.1","format":"rw.play/0.1"}')
 def test_unknown_fields_and_scenario_identity(self):
  self.data['expedition']['scenario_id']='scenario:other'
  with self.assertRaises(ValidationError):self.validate()
  self.data['expedition']['scenario_id']='scenario:platform';self.data['motion']['extra']=0
  with self.assertRaises(ValidationError):self.validate()
