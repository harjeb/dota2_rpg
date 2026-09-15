"""Check every explicit profile against checked-in native specials at low/high levels.
This validates catalogue keys and released record construction, not live Dota execution.
"""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
rows = json.loads((ROOT / 'data/native_skill_conditions.json').read_text(encoding='utf-8'))['rows']
definitions = {r['id']: r['native']['definition'] for r in rows}
definitions.update(json.loads((ROOT / 'scripts/data/campaign-neutral-native.json').read_text(encoding='utf-8'))['abilities'])
for name, fields in json.loads((ROOT / 'data/research/aoe_item_fields_20260915.json').read_text(encoding='utf-8'))['items'].items():
    definitions[name] = {'AbilityValues': {k: v for k, v in fields.items() if k != 'AbilityChannelTime'},
                         'AbilityChannelTime': fields.get('AbilityChannelTime', '')}

def number(value, high):
    if isinstance(value, dict):
        value = value.get('value', '')
    try:
        return float(str(value).split()[-1 if high else 0])
    except (ValueError, IndexError):
        return None

def lua(value):
    if isinstance(value, dict):
        return '{' + ','.join('[' + json.dumps(k) + ']=' + lua(v) for k, v in value.items()) + '}'
    return json.dumps(value)

runner = r'''
package.path='game/dota_addons/dota2_rpg/scripts/vscripts/?.lua;'..package.path
local P=require('tactics/aoe_profiles')
local A=require('tactics/aoe_threats')
local fixture=dofile(arg[1])
local function u(team)
 return {GetTeamNumber=function()return team end,GetAbsOrigin=function()return {x=0,y=0,z=0}end,
 CanEntityBeSeenByMyTeam=function()return true end,IsAlive=function()return true end}
end
local enemy,viewer,target=u(3),u(2),u(3)
local count=0
for name,p in pairs(P) do
 local d=assert(fixture[name],name..': native definition missing')
 local function check(spec)
  if type(spec)=='table' then check(spec[1]);check(spec[2])
  elseif type(spec)=='string' and spec:sub(1,1)~='@' then
   assert(d.values[spec]~=nil,name..': invalid native special '..spec)
  end
 end
 for _,key in ipairs({'radius','delay','duration','length','speed','travel_speed','inner_radius','end_radius'}) do check(p[key]) end
 local a={GetAbilityName=function()return name end,
 GetSpecialValueFor=function(_,k)return d.values[k]end,
 GetCursorPosition=function()return {x=100,y=0,z=0}end,
 GetCursorTarget=function()return target end,
 GetChannelTime=function()return d.channel end}
 A.Reset();A.Observe({viewer,enemy,target},0);A.OnExecuted(enemy,a,1)
 if p.channel_release then
  assert(#A.Threats(viewer,1)==0,name..': charge exposed')
  A.OnChannelEnd(enemy,a,1.5,false)
 end
 local r=assert(A.Threats(viewer,1.5)[1],name..': no valid release')
 assert(r.active_from==r.impact_at and r.active_until==r.expires_at,name..': timestamp aliases')
 assert(r.phase=='released' and r.shape==p.shape and r.radius>0,name..': shape contract')
 assert(#A.Threats(viewer,r.expires_at)==0,name..': expiry')
 count=count+1
end
assert(count>=70,'broad reviewed coverage regressed')
print('PASS native profile keys and release construction: '..count..' profiles')
'''.replace('A.Threats(viewer,1.5)[1]', 'A.Threats(viewer,p.channel_release and 1.5 or 1)[1]')

lua_bin = shutil.which('lua')
assert lua_bin, 'Lua required'
for high in (False, True):
    fixtures = {}
    for name, definition in definitions.items():
        values = {k: number(v, high) for k, v in definition.get('AbilityValues', {}).items()}
        values = {k: v for k, v in values.items() if v is not None}
        channel = values.get('AbilityChannelTime', number(definition.get('AbilityChannelTime', ''), high))
        fixtures[name] = {'values': values, 'channel': channel or 0}
    with tempfile.TemporaryDirectory() as temp:
        data = Path(temp) / 'fixtures.lua'
        script = Path(temp) / 'check.lua'
        data.write_text('return ' + lua(fixtures), encoding='utf-8')
        script.write_text(runner, encoding='utf-8')
        subprocess.run([lua_bin, str(script), str(data)], cwd=ROOT, check=True)
print('PASS all profiles against native low/high special values; no native engine proof claimed')
