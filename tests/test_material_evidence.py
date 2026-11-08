"""Resource accounting checks are independent of the GDScript simulation."""
import copy, importlib.util, json, pathlib, sys, unittest
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from check_snapshot import ValidationError,validate
class MaterialEvidenceTests(unittest.TestCase):
 def setUp(self):
  self.catalog={'format':'rw.catalog/0.1','materials':{'core:stone':{'stackable':True},'core:water_crystal':{'stackable':True,'bound_water_units':500},'user:reservoir':{'stackable':False,'state':'reservoir/0.1'}},'rules':{}}
  self.world={'format':'rw.world/0.2','actor':{'id':'player:local','cell':[-2,0]},'terrain':[{'cell':[1,1],'material_id':'core:water_crystal'}],'water':[{'cell':[2,0],'units':100}],'entities':{'format':'rw.instances/0.1','world_id':'world:forming','stacks':{'core:water_crystal':2},'instances':[{'id':'creation:caster','material_id':'user:reservoir','rules':[],'location':{'kind':'world','cell':[0,0]},'state':{'water_units':400,'capacity_units':2000,'light_on':False}}]}}
 def module(self):
  p=ROOT/'tools/check_material_evidence.py';self.assertTrue(p.exists(),'independent material checker missing')
  spec=importlib.util.spec_from_file_location('material_checker',p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
 def test_all_water_locations_counted(self):self.assertEqual(self.module().total_water(self.world,self.catalog),2000)
 def test_unknown_material_not_silently_zero(self):
  self.world['terrain'][0]['material_id']='core:unknown'
  with self.assertRaises(ValidationError):self.module().total_water(self.world,self.catalog)
 def test_fractional_water_rejected(self):
  self.world['water'][0]['units']=1.5
  with self.assertRaises(ValidationError):self.module().total_water(self.world,self.catalog)
 def test_invalid_bound_costs(self):
  for cost in [0,-1,1001,True,1.5,'500']:
   with self.subTest(cost=cost):
    c=copy.deepcopy(self.catalog);c['materials']['core:water_crystal']['bound_water_units']=cost
    with self.assertRaises(ValidationError):validate(json.dumps(self.world['entities']),c)
 def test_bound_cost_only_static_material(self):
  self.catalog['materials']['user:reservoir']['bound_water_units']=500
  with self.assertRaises(ValidationError):validate(json.dumps(self.world['entities']),self.catalog)
 def test_original_catalog_still_valid(self):
  self.catalog['materials'].pop('core:water_crystal');self.world['terrain']=[];self.world['entities']['stacks']={}
  self.assertEqual(self.module().total_water(self.world,self.catalog),500)
 def test_exact_material_simulation(self):
  m=self.module();d=m.material_expected();self.assertEqual(m.validate_material_output(json.dumps(d))['tick'],8)
 def test_bad_material_outputs(self):
  m=self.module()
  for mutation in ['water','position','tick','rule','terrain','stack','light']:
   with self.subTest(mutation=mutation):
    d=m.material_expected();w=d['world']
    if mutation=='water':w['entities']['instances'][0]['state']['water_units']=1
    elif mutation=='position':w['entities']['instances'][0]['location']['cell']=[4,0]
    elif mutation=='tick':d['tick']=True
    elif mutation=='rule':d['rules']['modules'][-1]['effects'].reverse()
    elif mutation=='terrain':w['terrain'].pop()
    elif mutation=='stack':w['entities']['stacks']={'core:water_crystal':1}
    else:w['entities']['instances'][0]['state']['light_on']=False
    with self.assertRaises(ValidationError):m.validate_material_output(json.dumps(d))
if __name__=='__main__':unittest.main()
