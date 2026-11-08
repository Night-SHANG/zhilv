import copy, json, pathlib, sys, unittest
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'tools'))
from check_world import validate_world
from check_snapshot import ValidationError
ROOT=pathlib.Path(__file__).resolve().parents[1]
class ActorBodyContract(unittest.TestCase):
 def setUp(self):
  self.catalog=json.loads((ROOT/'fixtures/catalog.json').read_text())
  self.world=json.loads((ROOT/'fixtures/world_checkpoint.json').read_text())
  self.world['format']='rw.world/0.3';self.world['water']=[]
  x,y=self.world['actor']['cell'];self.world['actor']['body_foot']=[x*1024+512,(y+1)*1024]
 def validate(self,d=None):return validate_world(json.dumps(self.world if d is None else d),self.catalog)
 def test_accepts_versioned_actor(self):self.assertEqual(self.validate()['actor'],self.world['actor'])
 def test_side_overlap_is_not_limited_to_anchor(self):
  self.world['terrain']=[];self.world['entities']['instances']=[]
  self.world['actor']['cell']=[0,0];self.world['actor']['body_foot']=[900,1024]
  self.validate();self.world['terrain']=[{'cell':[1,0],'material_id':'core:stone'}]
  with self.assertRaises(ValidationError):self.validate()
 def test_negative_floor(self):
  self.world['terrain']=[];self.world['entities']['instances']=[]
  self.world['actor']['cell']=[-1,0];self.world['actor']['body_foot']=[-124,1024]
  self.validate()
  self.world['actor']['cell']=[0,0]
  with self.assertRaises(ValidationError):self.validate()
 def test_invalid_pose_types(self):
  for value in (True, 1.5, '0',None):
   with self.subTest(value=value):
    d=copy.deepcopy(self.world);d['actor']['body_foot'][0]=value
    with self.assertRaises(ValidationError):self.validate(d)
 def test_body_outside_coordinate_limit(self):
  self.world['actor']['cell']=[-1000000,0];self.world['actor']['body_foot']=[-1024000000,1024]
  with self.assertRaises(ValidationError):self.validate()
 def test_old_formats_stay_supported(self):
  old=json.loads((ROOT/'fixtures/world_checkpoint.json').read_text());self.validate(old)
