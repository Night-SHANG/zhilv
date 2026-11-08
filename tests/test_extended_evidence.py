"""独立检查第二段的世界结果；不重写物理或任务运行器。"""
import copy,importlib.util,json,pathlib,sys,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from check_snapshot import ValidationError
class ExtendedEvidenceTests(unittest.TestCase):
 def setUp(self):
  self.s=json.loads((ROOT/'godot/content/fresh_expedition.json').read_text())
  self.c=json.loads((ROOT/'fixtures/fresh_contract.json').read_text())
  w=copy.deepcopy(self.s['world']);w['format']='rw.world/0.3';w['actor']['cell']=[6,2];w['actor']['body_foot']=[6656,3072];w['water']=[]
  removed=self.c['harvest_cells']+[[6,1],[5,1],[7,1],[8,1]]
  w['terrain']=[t for t in w['terrain'] if t['cell'] not in removed];w['entities']['stacks']={'core:stone':4}
  w['entities']['instances'][0]['state']['water_units']=500
  w['entities']['instances'] += [
   {'id':self.c['vessel_id'],'material_id':'user:reservoir','location':{'kind':'world','cell':[8,1]},'rules':[{'id':self.c['pump']['id'],'version':1}],'state':{'water_units':5500,'capacity_units':6000,'light_on':False}},
   {'id':self.c['lamp_id'],'material_id':'user:crystal','location':{'kind':'world','cell':[7,0]},'rules':[{'id':'core:portable_lamp','version':1}],'state':{'water_units':0,'capacity_units':1,'light_on':True}}]
  rules=copy.deepcopy(self.s['rules']);rules['modules'].append(copy.deepcopy(self.c['pump']))
  self.d={'format':'rw.workspace/0.1','editor':{'selected':self.c['vessel_id'],'tool':'vessel','drafts':{self.c['vessel_id']:copy.deepcopy(self.c['unfinished'])}},'play':{'format':'rw.play/0.1','motion':{'velocity_x':0,'velocity_y':0},'expedition':{'format':'rw.expedition/0.1','scenario_id':self.s['definition']['id'],'scenario_version':self.s['definition']['version'],'completed':['goal:ruins','goal:irrigate','goal:lower_archive','goal:lower_supply'],'simulation':{'format':'rw.simulation/0.2','tick':300,'clock':{**self.s['clock'],'paused':True},'world':w,'rules':rules}}}}
 def validate(self):
  p=ROOT/'tools/check_extended_evidence.py';self.assertTrue(p.exists(),'extended evidence checker missing')
  spec=importlib.util.spec_from_file_location('extended',p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  return m.validate_extended_expedition(json.dumps(self.d),self.s,self.c)
 def world(self):return self.d['play']['expedition']['simulation']['world']
 def test_complete_same_world_route(self):self.assertEqual(self.validate()['format'],'rw.workspace/0.1')
 def test_old_version_cannot_claim_new_goals(self):
  self.d['play']['expedition']['scenario_version']=1
  with self.assertRaises(ValidationError):self.validate()
 def test_missing_or_skipped_goal(self):
  self.d['play']['expedition']['completed'].pop(2)
  with self.assertRaises(ValidationError):self.validate()
 def test_not_real_lower_position(self):
  self.world()['actor']['cell']=[-2,0];self.world()['actor']['body_foot']=[-1536,1024]
  with self.assertRaises(ValidationError):self.validate()
 def test_new_water(self):
  self.world()['entities']['instances'][1]['state']['water_units']+=1
  with self.assertRaises(ValidationError):self.validate()
 def test_replaced_carrier_identity(self):
  self.world()['entities']['instances'][1]['id']='creation:fake'
  with self.assertRaises(ValidationError):self.validate()
 def test_inventory_not_supply_station(self):
  self.world()['entities']['instances'][1]['location']={'kind':'inventory','owner':'player:local'}
  with self.assertRaises(ValidationError):self.validate()
 def test_original_lamp_not_reused(self):
  self.world()['entities']['instances'][2]['location']['cell']=[9,-1]
  with self.assertRaises(ValidationError):self.validate()
 def test_materials_minted(self):
  self.world()['entities']['stacks']['core:stone']+=1
  with self.assertRaises(ValidationError):self.validate()
 def test_unexplored_terrain(self):
  self.world()['terrain'].append({'cell':[7,1],'material_id':'core:stone'})
  with self.assertRaises(ValidationError):self.validate()
 def test_discarded_draft(self):
  self.d['editor']['drafts']={}
  with self.assertRaises(ValidationError):self.validate()
 def test_replaced_world(self):
  self.world()['entities']['world_id']='world:new'
  with self.assertRaises(ValidationError):self.validate()
if __name__=='__main__':unittest.main()
