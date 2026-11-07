"""空包采集→制作→创作→恢复→目标完成的独立输出检查。"""
import copy, importlib.util, json, pathlib, sys, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from check_snapshot import ValidationError
class FreshEvidenceTests(unittest.TestCase):
 def setUp(self):
  self.s=json.loads((ROOT/'godot/content/fresh_expedition.json').read_text())
  self.c=json.loads((ROOT/'fixtures/fresh_contract.json').read_text())
  w=copy.deepcopy(self.s['world']);w['format']='rw.world/0.3';w['actor']['cell']=[-2,0];w['actor']['body_foot']=[-1536,1024];w['water']=[]
  w['terrain']=[t for t in w['terrain'] if t['cell'] not in self.c['harvest_cells']]
  w['entities']['instances'][0]['state']['water_units']=500
  w['entities']['instances'] += [
    {'id':self.c['vessel_id'],'material_id':'user:reservoir','location':{'kind':'inventory','owner':'player:local'},'state':{'water_units':5500,'capacity_units':6000,'light_on':False},'rules':[{'id':self.c['pump']['id'],'version':1}]},
    {'id':self.c['lamp_id'],'material_id':'user:crystal','location':{'kind':'world','cell':[9,-1]},'state':{'water_units':0,'capacity_units':1,'light_on':True},'rules':[{'id':'core:portable_lamp','version':1}]}]
  rules=copy.deepcopy(self.s['rules']);rules['modules'].append(copy.deepcopy(self.c['pump']))
  play={'format':'rw.play/0.1','motion':{'velocity_x':0,'velocity_y':0},'expedition':{'format':'rw.expedition/0.1','scenario_id':self.s['definition']['id'],'scenario_version':1,'completed':self.c['completed'],'simulation':{'format':'rw.simulation/0.2','tick':100,'clock':{**self.s['clock'],'paused':True},'world':w,'rules':rules}}}
  self.d={'format':'rw.workspace/0.1','play':play,'editor':{'selected':self.c['vessel_id'],'tool':'lamp','drafts':{self.c['vessel_id']:copy.deepcopy(self.c['unfinished'])}}}
 def validate(self,text=None):
  p=ROOT/'tools/check_fresh_evidence.py';self.assertTrue(p.exists(),'fresh checkpoint independent validator missing')
  spec=importlib.util.spec_from_file_location('fresh',p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  return m.validate_fresh_expedition(json.dumps(self.d) if text is None else text,self.s,self.c)
 def test_valid_finished_route(self):self.assertEqual(self.validate()['format'],'rw.workspace/0.1')
 def test_duplicate_json_rejected(self):
  with self.assertRaises(ValidationError):self.validate('{"format":"rw.workspace/0.1","format":"rw.workspace/0.1"}')
 def test_world_identity(self):
  self.d['play']['expedition']['simulation']['world']['entities']['world_id']='world:other'
  with self.assertRaises(ValidationError):self.validate()
 def test_missing_goal(self):
  self.d['play']['expedition']['completed']=[]
  with self.assertRaises(ValidationError):self.validate()
 def test_free_materials(self):
  self.d['play']['expedition']['simulation']['world']['entities']['stacks']={'core:stone':1}
  with self.assertRaises(ValidationError):self.validate()
 def test_minted_water(self):
  self.d['play']['expedition']['simulation']['world']['entities']['instances'][1]['state']['water_units']+=1
  with self.assertRaises(ValidationError):self.validate()
 def test_shared_or_changed_carrier_id(self):
  self.d['play']['expedition']['simulation']['world']['entities']['instances'][1]['id']='creation:vessel'
  with self.assertRaises(ValidationError):self.validate()
 def test_ungathered_stone(self):
  self.d['play']['expedition']['simulation']['world']['terrain'].append({'cell':[0,-2],'material_id':'core:stone'})
  with self.assertRaises(ValidationError):self.validate()
 def test_missing_or_published_draft(self):
  self.d['editor']['drafts']={}
  with self.assertRaises(ValidationError):self.validate()
 def test_changed_unfinished_node(self):
  self.d['editor']['drafts'][self.c['vessel_id']]['nodes'][-1]['op']='move'
  with self.assertRaises(ValidationError):self.validate()
 def test_fraction_and_bool_integer(self):
  for value in [True,1.5]:
   self.d['play']['expedition']['simulation']['tick']=value
   with self.assertRaises(ValidationError):self.validate()
 def test_unknown_editor_field_or_selection(self):
  self.d['editor']['selected']='creation:missing'
  with self.assertRaises(ValidationError):self.validate()
 def test_changed_published_rule(self):
  self.d['play']['expedition']['simulation']['rules']['modules'][-1]['effects']=[]
  with self.assertRaises(ValidationError):self.validate()
if __name__=='__main__':unittest.main()
