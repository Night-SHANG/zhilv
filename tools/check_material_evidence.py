"""独立核验凝结地形、封水账本及搭路终态；不实现另一个模拟器。"""
from __future__ import annotations
import copy,json
from check_snapshot import exact,integer,parse_bounded,require
from check_world import validate_world
from check_rule_evidence import canonical_pack
from check_play_evidence import validate_play_checkpoint

def total_water(world:dict,catalog:dict)->int:
    w=validate_world(json.dumps(world),catalog)
    def cost(mid):return catalog['materials'][mid].get('bound_water_units',0)
    return (sum(v['units'] for v in w.get('water',[]))+
            sum(e['state']['water_units'] for e in w['entities']['instances'])+
            sum(cost(t['material_id']) for t in w['terrain'])+
            sum(cost(mid)*quantity for mid,quantity in w['entities']['stacks'].items()))

def node(id,op,inputs=None,config=None):return dict(id=id,op=op,inputs=inputs or {},config=config or {})
def formation_program(id,version,dx,dy):
    return dict(id=id,version=version,parameters={},effects=['form'],nodes=[
        node('water','read_state',config={'field':'water_units'}),node('cost','int',config={'value':500}),
        node('lacking','lt',{'a':'water','b':'cost'}),node('enough','not',{'value':'lacking'}),
        node('target','cell_empty',config={'dx':dx,'dy':dy}),node('ready','and',{'a':'enough','b':'target'}),
        node('form','form_material',{'when':'ready'},{'dx':dx,'dy':dy,'material':'core:water_crystal'})])

def material_expected():
    modules=[]
    for id,forming in [('user:form',True),('user:recover',False)]:
        config={'dx':1,'dy':0}
        if not forming:config['material']='core:water_crystal'
        modules.append(dict(id=id,version=1,parameters={},effects=['act'],nodes=[node('ready','cell_empty' if forming else 'terrain_is',config=config),node('act','form_material' if forming else 'recover_material',{'when':'ready'},{'dx':1,'dy':0,'material':'core:water_crystal'})]))
    modules.append(dict(id='user:builder',version=1,parameters={},effects=['move','form','lamp'],nodes=[node('yes','bool',config={'value':True}),node('move','move',{'when':'yes'},{'dx':1,'dy':0}),node('form','form_material',{'when':'yes'},{'dx':0,'dy':1,'material':'core:water_crystal'}),node('lamp','set_light',{'when':'yes','value':'yes'})]))
    world=dict(format='rw.world/0.2',actor={'id':'player:local','cell':[-2,0]},terrain=[{'cell':[x,1],'material_id':'core:water_crystal'} for x in [1,2,3]],water=[],entities=dict(format='rw.instances/0.1',world_id='world:forming',stacks={},instances=[dict(id='creation:caster',material_id='user:reservoir',rules=[dict(id='user:builder',version=1)],state=dict(water_units=0,capacity_units=2000,light_on=True),location=dict(kind='world',cell=[3,0]))]))
    return dict(format='rw.simulation/0.1',tick=8,world=world,rules={'format':'rw.rules/0.1','modules':modules})

def validate_material_output(text:str)->dict:
    d=parse_bounded(text);exact(d,{'format','tick','world','rules'},'simulation')
    expected=material_expected();integer(d['tick'],8,8,'tick');require(d['format']==expected['format'],'模拟格式不符')
    catalog=dict(format='rw.catalog/0.1',materials={'core:stone':{'stackable':True},'core:water_crystal':{'stackable':True,'bound_water_units':500},'user:reservoir':{'stackable':False,'state':'reservoir/0.1'}},rules={m['id']:[1] for m in expected['rules']['modules']})
    require(total_water(d['world'],catalog)==1500,'移动铺路没有保持1500总水')
    require(d['world']==expected['world'],'移动、地形、实例状态或身份不符')
    require(canonical_pack(d['rules'])==canonical_pack(expected['rules']),'规则不符')
    return d

def validate_ascent_output(text:str,scenario:dict,contract:dict,stone:bool=False)->dict:
    d=parse_bounded(text);exact(d,{'format','play','editor'},'workspace');require(d['format']=='rw.workspace/0.1','工作区格式错误')
    rules=copy.deepcopy(scenario['rules']);rules['modules'].append(copy.deepcopy(contract['pump']))
    rid=contract['pump']['id']
    if not stone:rules['modules'] += [formation_program(rid,2,-1,0),formation_program(rid,3,0,-1)]
    play=validate_play_checkpoint(json.dumps(d['play']),scenario['catalog'],scenario['definition'],rules)
    exp=play['expedition'];w=exp['simulation']['world']
    require(exp['completed']==[g['id'] for g in scenario['definition']['objectives']],'五项目标未完成')
    require(w['actor']['id']==scenario['world']['actor']['id'] and w['actor']['cell']==[0,-3],'没有真实到达高处')
    require(exp['simulation']['clock']=={**scenario['clock'],'paused':True},'昼夜或暂停被更改')
    require(w['entities']['world_id']==scenario['world']['entities']['world_id'],'世界身份改变')
    require(w['entities']['stacks']=={'core:stone':2 if stone else 4},'原料未正确消耗')
    removed=contract['harvest_cells']+[[6,1],[5,1],[7,1],[8,1]]
    tiles={tuple(t['cell']):t['material_id'] for t in scenario['world']['terrain'] if t['cell'] not in removed}
    for pos in [(0,-2),(1,-1)]:tiles[pos]='core:stone' if stone else 'core:water_crystal'
    require({tuple(t['cell']):t['material_id'] for t in w['terrain']}==tiles,'实际台阶或地形不符')
    entities={e['id']:e for e in w['entities']['instances']}
    require(set(entities)=={'creation:plot',contract['vessel_id'],contract['lamp_id']},'没有复用原造物')
    v=entities[contract['vessel_id']];lamp=entities[contract['lamp_id']]
    require(v['material_id']=='user:reservoir' and v['location']=={'kind':'inventory','owner':w['actor']['id']},'容器没有回收')
    require(v['state']['capacity_units']==6000 and v['state']['water_units']>=(4500 if stone else 3500) and v['state']['light_on'] is False,'容器状态不符')
    require(v['rules']==[{'id':rid,'version':1 if stone else 3}],'绑定版本不符')
    require(lamp==dict(id=contract['lamp_id'],material_id='user:crystal',rules=[dict(id='core:portable_lamp',version=1)],state=dict(water_units=0,capacity_units=1,light_on=True),location=dict(kind='world',cell=[-1,-3])),'原夜灯未复用')
    plot=copy.deepcopy(scenario['world']['entities']['instances'][0]);plot['state']['water_units']=500
    require(entities['creation:plot']==plot,'营地资源改变')
    resource_catalog=copy.deepcopy(scenario['catalog'])
    for m in rules['modules']:
        versions=resource_catalog['rules'].setdefault(m['id'],[])
        if m['version'] not in versions:versions.append(m['version'])
    require(total_water(w,resource_catalog)==6000,'总水量不守恒')
    e=d['editor'];exact(e,{'selected','tool','drafts'},'editor')
    require(e['selected']==contract['lamp_id' if stone else 'vessel_id'] and e['tool']==('stone' if stone else 'vessel'),'选择工具错误')
    expected_draft=contract['unfinished'] if stone else formation_program(rid,1,0,-1)
    require(set(e['drafts'])=={contract['vessel_id']},'草稿对象错误')
    require(canonical_pack({'format':'rw.rules/0.1','modules':[e['drafts'][contract['vessel_id']]]})==canonical_pack({'format':'rw.rules/0.1','modules':[expected_draft]}),'未应用草稿不符')
    return d
