"""只独立读取原生流程输出，不在Python再实现水引擎或证明游戏好玩。"""
import copy
import importlib.util
import json
import pathlib
import sys
import unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tools'))
from check_snapshot import ValidationError
from check_world import validate_world

class EnvironmentEvidenceTests(unittest.TestCase):
    def setUp(self):
        self.scenario=json.loads((ROOT/'godot/content/wet_ruins.json').read_text())
        self.contract=json.loads((ROOT/'fixtures/environment_contract.json').read_text())
        self.data={'format':'rw.expedition_evidence/0.1','routes':{}}
        for name,c in self.contract['routes'].items():
            w=copy.deepcopy(self.scenario['world'])
            w['actor']['cell']=[-2,0]
            by_id={e['id']:e for e in w['entities']['instances']}
            by_id['creation:vessel']['state']['water_units']=c['vessel_water']
            by_id['creation:plot']['state']['water_units']=500
            by_id['creation:lamp']['state']['light_on']=True
            by_id['creation:lamp']['location']={'kind':'world','cell':[9,-1]}
            total=6000-c['vessel_water']-500
            w['water']=[]
            for x in range(2,8):
                n=min(total,1000)
                if n: w['water'].append({'cell':[x,0],'units':n}); total-=n
            rules=copy.deepcopy(self.scenario['rules'])
            if c['authored_rule']:
                rules['modules'].append(copy.deepcopy(self.contract['pump']))
                by_id['creation:vessel']['rules']=[{'id':'user:reusable_water_pump','version':1}]
            if c['mined']:
                w['terrain']=[t for t in w['terrain'] if t['cell']!=[1,1]]
                w['entities']['stacks']['core:stone']+=1
            cp={'format':'rw.expedition/0.1','scenario_id':'scenario:wet_ruins','scenario_version':1,'completed':copy.deepcopy(self.contract['completed']),'simulation':{'format':'rw.simulation/0.2','tick':c['tick'],'clock':{'cycle_ticks':120,'daylight_ticks':60,'paused':False},'world':w,'rules':rules}}
            self.data['routes'][name]={'checkpoint':json.dumps(cp),'total_water':6000,'plot_water':500,'mined':c['mined'],'authored_rule':c['authored_rule']}
    def verify(self):
        path=ROOT/'tools/check_environment_evidence.py'
        self.assertTrue(path.exists(),'environment evidence reader not implemented')
        spec=importlib.util.spec_from_file_location('check_environment_evidence',path)
        m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
        return m.validate_expedition_result(json.dumps(self.data),self.scenario,self.contract)
    def mutate(self,fn,route='manual'):
        d=json.loads(self.data['routes'][route]['checkpoint']);fn(d);self.data['routes'][route]['checkpoint']=json.dumps(d)
    def test_complete_three_routes(self): self.verify()
    def test_missing_route(self):
        del self.data['routes']['drainage']
        with self.assertRaises(ValidationError):self.verify()
    def test_claimed_total_cannot_hide_actual_loss(self):
        self.mutate(lambda d:d['simulation']['world']['water'].clear())
        with self.assertRaises(ValidationError):self.verify()
    def test_wrong_goal(self):
        self.mutate(lambda d:d['completed'].pop())
        with self.assertRaises(ValidationError):self.verify()
    def test_paused_save_not_demo_end(self):
        self.mutate(lambda d:d['simulation']['clock'].update(paused=True))
        with self.assertRaises(ValidationError):self.verify()
    def test_fractional_clock(self):
        self.mutate(lambda d:d['simulation']['clock'].update(cycle_ticks=120.0))
        with self.assertRaises(ValidationError):self.verify()
    def test_changed_program_rejected(self):
        self.mutate(lambda d:d['simulation']['rules']['modules'][-1]['nodes'][0].update(op='system_exec'),'authored')
        with self.assertRaises(ValidationError):self.verify()
    def test_water_solid_overlap(self):
        self.mutate(lambda d:d['simulation']['world']['water'][0].update(cell=[2,1]))
        with self.assertRaises(ValidationError):self.verify()
    def test_water_overfill(self):
        self.mutate(lambda d:d['simulation']['world']['water'][0].update(units=1001))
        with self.assertRaises(ValidationError):self.verify()
    def test_boolean_water_rejected(self):
        self.mutate(lambda d:d['simulation']['world']['water'][0].update(units=True))
        with self.assertRaises(ValidationError):self.verify()
    def test_wrong_actor_destination(self):
        self.mutate(lambda d:d['simulation']['world']['actor'].update(cell=[0,0]))
        with self.assertRaises(ValidationError):self.verify()
    def test_terrain_invented_by_route(self):
        self.mutate(lambda d:d['simulation']['world']['terrain'].pop())
        with self.assertRaises(ValidationError):self.verify()
    def test_lost_dynamic_binding(self):
        self.mutate(lambda d:d['simulation']['world']['entities']['instances'][0]['rules'].clear(),'authored')
        with self.assertRaises(ValidationError):self.verify()
    def test_extra_authority_rejected(self):
        self.data['catalog']=self.scenario['catalog']
        with self.assertRaises(ValidationError):self.verify()

class WaterWorldContractTests(unittest.TestCase):
    def setUp(self):
        self.s=json.loads((ROOT/'godot/content/wet_ruins.json').read_text())
    def verify(self):return validate_world(json.dumps(self.s['world']),self.s['catalog'])
    def test_new_water_world_valid(self):self.verify()
    def test_missing_water_layer(self):
        del self.s['world']['water']
        with self.assertRaises(ValidationError):self.verify()
    def test_duplicate_water(self):
        self.s['world']['water'].append(copy.deepcopy(self.s['world']['water'][0]))
        with self.assertRaises(ValidationError):self.verify()
    def test_zero_water_not_saved(self):
        self.s['world']['water'][0]['units']=0
        with self.assertRaises(ValidationError):self.verify()
    def test_fractional_water_not_saved(self):
        self.s['world']['water'][0]['units']=0.5
        with self.assertRaises(ValidationError):self.verify()
    def test_actor_can_remain_in_flooded_cell(self):
        self.s['world']['water'].append({'cell':[0,0],'units':1000})
        self.verify()
    def test_legacy_world_does_not_silently_drop_water(self):
        self.s['world']['format']='rw.world/0.1'
        with self.assertRaises(ValidationError):self.verify()
