"""Both exploration outputs have specific independently checked end states."""
import copy,json,unittest
import test_extended_evidence
from check_material_evidence import formation_program,validate_ascent_output
from check_snapshot import ValidationError
class AscentEvidenceTests(unittest.TestCase):
 def setup_data(self,stone=False):
  base=test_extended_evidence.ExtendedEvidenceTests();base.setUp();self.s,self.c,self.d=base.s,base.c,base.d;self.stone=stone
  exp=self.d['play']['expedition'];sim=exp['simulation'];w=sim['world'];rid=self.c['pump']['id']
  exp['completed']=[g['id'] for g in self.s['definition']['objectives']]
  w['actor'].update(cell=[0,-3],body_foot=[512,-2048]);w['entities']['stacks']={'core:stone':2 if stone else 4}
  w['terrain'] += [dict(cell=[x,y],material_id='core:stone' if stone else 'core:water_crystal') for x,y in [(0,-2),(1,-1)]]
  v=w['entities']['instances'][1];v['location']={'kind':'inventory','owner':'player:local'};v['state']['water_units']=5500 if stone else 4500
  v['rules'][0]['version']=1 if stone else 3;w['entities']['instances'][2]['location']['cell']=[-1,-3]
  if not stone:sim['rules']['modules'] += [formation_program(rid,2,-1,0),formation_program(rid,3,0,-1)]
  self.d['editor'].update(selected=self.c['lamp_id' if stone else 'vessel_id'],tool='stone' if stone else 'vessel')
  if not stone:self.d['editor']['drafts'][self.c['vessel_id']]=formation_program(rid,1,0,-1)
 def check_output(self):return validate_ascent_output(json.dumps(self.d),self.s,self.c,self.stone)
 def test_crystal_route(self):self.setup_data();self.check_output()
 def test_stone_route(self):self.setup_data(True);self.check_output()
 def test_wrong_selection_not_forgiven(self):
  self.setup_data(True);self.d['editor']['selected']=self.c['vessel_id']
  with self.assertRaises(ValidationError):self.check_output()
 def test_missing_step(self):
  self.setup_data();self.d['play']['expedition']['simulation']['world']['terrain'].pop()
  with self.assertRaises(ValidationError):self.check_output()
 def test_minted_water(self):
  self.setup_data();self.d['play']['expedition']['simulation']['world']['entities']['instances'][1]['state']['water_units']+=1
  with self.assertRaises(ValidationError):self.check_output()
 def test_actor_not_at_goal(self):
  self.setup_data();self.d['play']['expedition']['simulation']['world']['actor'].update(cell=[3,0],body_foot=[3584,1024])
  with self.assertRaises(ValidationError):self.check_output()
 def test_unpaid_stone(self):
  self.setup_data(True);self.d['play']['expedition']['simulation']['world']['entities']['stacks']['core:stone']=4
  with self.assertRaises(ValidationError):self.check_output()
 def test_old_binding_cannot_claim_new_graph(self):
  self.setup_data();self.d['play']['expedition']['simulation']['world']['entities']['instances'][1]['rules'][0]['version']=1
  with self.assertRaises(ValidationError):self.check_output()
if __name__=='__main__':unittest.main()
