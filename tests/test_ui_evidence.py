"""界面完整路线产物的独立结构/资源/版本检查。"""
import copy,json,pathlib,sys,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from check_snapshot import ValidationError
class UiEvidenceTests(unittest.TestCase):
 def setUp(self):
  self.s=json.loads((ROOT/'godot/content/first_expedition.json').read_text());self.c=json.loads((ROOT/'fixtures/ui_contract.json').read_text())
  w=copy.deepcopy(self.s['world']);w['format']='rw.world/0.3';w['actor']['cell']=[-2,0];w['actor']['body_foot']=[-1536,1024];w['water']=[]
  for e in w['entities']['instances']:
   if e['id']=='creation:vessel':e['state']['water_units']=5500;e['rules']=[{'id':self.c['pump']['id'],'version':1}]
   if e['id']=='creation:plot':e['state']['water_units']=500
   if e['id']=='creation:lamp':e['state']['light_on']=True;e['location']={'kind':'world','cell':[9,-1]}
  rules=copy.deepcopy(self.s['rules']);rules['modules'].append(copy.deepcopy(self.c['pump']))
  self.d={'format':'rw.play/0.1','motion':{'velocity_x':0,'velocity_y':0},'expedition':{'format':'rw.expedition/0.1','scenario_id':self.s['definition']['id'],'scenario_version':1,'completed':self.c['completed'],'simulation':{'format':'rw.simulation/0.2','tick':100,'clock':{**self.s['clock'],'paused':True},'world':w,'rules':rules}}}
 def validate(self):
  import check_play_evidence as m
  self.assertTrue(hasattr(m,'validate_ui_expedition'),'UI output validator missing')
  return m.validate_ui_expedition(json.dumps(self.d),self.s,self.c)
 def test_valid_ui_output(self):self.assertEqual(self.validate()['format'],'rw.play/0.1')
 def test_missing_goal(self):
  self.d['expedition']['completed']=[]
  with self.assertRaises(ValidationError):self.validate()
 def test_minted_water(self):
  for e in self.d['expedition']['simulation']['world']['entities']['instances']:
   if e['id']=='creation:vessel':e['state']['water_units']+=1
  with self.assertRaises(ValidationError):self.validate()
 def test_changed_program(self):
  self.d['expedition']['simulation']['rules']['modules'][-1]['nodes'][5]['config']={'value':999}
  with self.assertRaises(ValidationError):self.validate()
