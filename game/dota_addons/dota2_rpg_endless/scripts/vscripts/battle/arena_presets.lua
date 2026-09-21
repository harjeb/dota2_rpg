-- Test opponents are generated locally and never consume an arena series.
local Presets = {}
local gear = {
    lower = {"item_power_treads", "item_bracer", "item_wraith_band", "item_null_talisman"},
    similar = {"item_power_treads", "item_black_king_bar", "item_ultimate_scepter", "item_assault"},
    higher = {"item_travel_boots_2", "item_black_king_bar", "item_ultimate_scepter", "item_heart", "item_shivas_guard", "item_bloodthorn"},
}
local positions = {{-720,-220},{-880,0},{-720,220},{-520,-340},{-520,340}}
function Presets.Generate(catalog, strength, rating, random)
    random = random or RandomInt or math.random
    local pool = {}; for _,name in ipairs(catalog) do pool[#pool+1]=name end
    assert(#pool >= 5 and gear[strength], "invalid test opponent request")
    local team = {version="arena-team-v1", heroes={}, storage={}}
    for i=1,5 do
        local name = table.remove(pool, random(1,#pool))
        local items = {}
        for slot,item in ipairs(gear[strength]) do items[#items+1]={slot=slot-1,name=item,charges=0,secondary_charges=0} end
        team.heroes[i]={id="h"..i,name=name,level=30,position={x=positions[i][1]+random(-80,80),y=positions[i][2]+random(-60,60)},
            facing=0,abilities={},ability_points=0,items=items,shard=strength=="higher",scepter=false,rules={}}
    end
    return {id="practice",player_name="Practice",rating=math.max(0,(rating or 1500)+(strength=="lower" and -300 or strength=="higher" and 300 or 0)),
        preset=true,team=team,strength=strength}
end
return Presets
