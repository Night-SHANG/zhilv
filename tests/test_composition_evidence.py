"""独立产物验收器的错误记忆；没有复制或替代Godot解释器。"""
import copy,importlib.util,json,pathlib,sys,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tools'))
from check_snapshot import ValidationError
class CompositionEvidenceTests(unittest.TestCase):
 def setUp(self):
  self.c=json.loads((ROOT/'fixtures/composition_expected.json').read_text())
  def world(a,b,bound_b=True):
   entities=[]
   for name,x,water,bound in [('a',0,a,True),('b',2,b,bound_b)]:
    entities.append(dict(id='creation:'+name,material_id='user:reservoir',state=dict(water_units=water,capacity_units=1000,light_on=bound),location=dict(kind='world',cell=[x,0]),rules=[dict(id='user:actor_'+name,version=1)] if bound else []))
   return dict(format='rw.world/0.2',actor=dict(id='player:local',cell=[1,-2]),terrain=[dict(cell=[1,1],material_id='core:stone')],water=[dict(cell=[1,0],units=1000-a-b)],entities=dict(format='rw.instances/0.1',world_id='world:words',stacks={},instances=entities))
  keys={tuple(k) for k in self.c['export_keys']}
  subset=dict(format='rw.rules/0.1',modules=[m for m in self.c['rules']['modules'] if (m['id'],m['version']) in keys])
  self.d=dict(format='rw.composition_evidence/0.1',simulation=dict(format='rw.simulation/0.1',tick=2,world=world(200,400),rules=copy.deepcopy(self.c['rules'])),scroll=dict(format='rw.scroll/0.1',entry=dict(id='user:actor_a',version=1),rules=copy.deepcopy(subset)),imported=dict(format='rw.simulation/0.1',tick=1,world=world(100,0,False),rules=copy.deepcopy(subset)))
 def validate(self,text=None):
  path=ROOT/'tools/check_composition_evidence.py';self.assertTrue(path.exists(),'independent composition checker missing')
  spec=importlib.util.spec_from_file_location('composition_checker',path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
  return m.validate_composition_evidence(json.dumps(self.d) if text is None else text,self.c)
 def test_valid(self):self.assertEqual(self.validate()['format'],'rw.composition_evidence/0.1')
 def test_duplicate_key(self):
  with self.assertRaises(ValidationError):self.validate('{"format":"x","format":"x"}')
 def test_wrong_output_amount(self):
  self.d['simulation']['world']['entities']['instances'][0]['state']['water_units']=201
  with self.assertRaises(ValidationError):self.validate()
 def test_wrong_parameter_value(self):
  self.d['simulation']['rules']['modules'][0]['parameters']['rate']['default']=999
  with self.assertRaises(ValidationError):self.validate()
 def test_false_boolean_not_integer(self):
  self.d['imported']['tick']=True
  with self.assertRaises(ValidationError):self.validate()
 def test_different_world(self):
  self.d['simulation']['world']['entities']['world_id']='world:other'
  with self.assertRaises(ValidationError):self.validate()
 def test_leaked_dependency(self):
  self.d['scroll']['rules']['modules'].append(copy.deepcopy(self.c['rules']['modules'][1]))
  with self.assertRaises(ValidationError):self.validate()
 def test_missing_dependency(self):
  self.d['scroll']['rules']['modules'].pop()
  with self.assertRaises(ValidationError):self.validate()
 def test_caller_upgraded_silently(self):
  self.d['simulation']['rules']['modules'][3]['nodes'][2]['config']['version']=2
  with self.assertRaises(ValidationError):self.validate()
 def test_implicit_second_binding(self):
  self.d['imported']['world']['entities']['instances'][1]['rules']=[dict(id='user:actor_a',version=1)]
  with self.assertRaises(ValidationError):self.validate()
 def test_incomplete_envelope(self):
  del self.d['imported']
  with self.assertRaises(ValidationError):self.validate()
 def test_effect_order_changed(self):
  self.d['simulation']['rules']['modules'][3]['effects'].reverse()
  with self.assertRaises(ValidationError):self.validate()
if __name__=='__main__':unittest.main()
