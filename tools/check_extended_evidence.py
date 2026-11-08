"""独立检查完整下层探索结果；不重写物理、规则和任务运行器。"""
from __future__ import annotations
import copy
import json
from check_snapshot import exact,parse_bounded,require
from check_play_evidence import validate_play_checkpoint
from check_rule_evidence import canonical_pack

def validate_extended_expedition(text:str,scenario:dict,contract:dict)->dict:
    data=parse_bounded(text)
    exact(data,{'format','play','editor'},'workspace')
    require(data['format']=='rw.workspace/0.1','未知工作区格式')
    rules=copy.deepcopy(scenario['rules']);rules['modules'].append(copy.deepcopy(contract['pump']))
    play=validate_play_checkpoint(json.dumps(data['play'],ensure_ascii=False),scenario['catalog'],scenario['definition'],rules)
    exp=play['expedition'];sim=exp['simulation'];world=sim['world'];original=scenario['world']
    require(exp['completed']==['goal:ruins','goal:irrigate','goal:lower_archive','goal:lower_supply'],'后续目标未全部完成')
    require(world['entities']['world_id']==original['entities']['world_id'],'更换了世界')
    require(world['actor']['id']==original['actor']['id'] and world['actor']['cell']==[6,2],'未实际到达下层')
    require(sim['clock']=={**scenario['clock'],'paused':True},'收尾应暂停且保留昼夜')
    require(world['entities']['stacks']=={'core:stone':4},'后续仅挖四块地板，不能赠送材料')
    removed=contract['harvest_cells']+[[6,1],[5,1],[7,1],[8,1]]
    expected={tuple(t['cell']):t['material_id'] for t in original['terrain'] if t['cell'] not in removed}
    require({tuple(t['cell']):t['material_id'] for t in world['terrain']}==expected,'地形改变不符合实际探索')
    entities={e['id']:e for e in world['entities']['instances']}
    require(set(entities)=={'creation:plot',contract['vessel_id'],contract['lamp_id']},'没有复用原来的造物')
    vessel=entities[contract['vessel_id']];lamp=entities[contract['lamp_id']];plot=entities['creation:plot']
    require(vessel['material_id']=='user:reservoir' and vessel['location']=={'kind':'world','cell':[8,1]},'容器未成为下层储水点')
    require(vessel['state']['water_units']>=4500 and vessel['state']['capacity_units']==6000 and vessel['state']['light_on'] is False,'复用的容器状态错误')
    require(vessel['rules']==[{'id':contract['pump']['id'],'version':1}],'原有程序被替换')
    require(lamp=={'id':contract['lamp_id'],'material_id':'user:crystal','location':{'kind':'world','cell':[7,0]},'rules':[{'id':'core:portable_lamp','version':1}],'state':{'capacity_units':1,'water_units':0,'light_on':True}},'没有复用同一灯照亮下层')
    expected_plot=copy.deepcopy(original['entities']['instances'][0]);expected_plot['state']['water_units']=500
    require(plot==expected_plot,'首段交付被覆盖或重复发奖')
    total=sum(e['state']['water_units'] for e in entities.values())+sum(w['units'] for w in world['water'])
    require(total==contract['initial_water'],'第二段凭空增减水量')
    editor=data['editor'];exact(editor,{'selected','tool','drafts'},'editor')
    require(editor['selected']==contract['vessel_id'] and editor['tool']=='vessel','末端选中工具错误')
    require(type(editor['drafts']) is dict and set(editor['drafts'])=={contract['vessel_id']},'草稿丢失或对象错误')
    require(canonical_pack({'format':'rw.rules/0.1','modules':[editor['drafts'][contract['vessel_id']]]})==canonical_pack({'format':'rw.rules/0.1','modules':[contract['unfinished']]}),'第二段未保留未发布草稿')
    return data
