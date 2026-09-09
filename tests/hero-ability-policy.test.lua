local root = os.getenv("DOTA_RPG_ROOT") or "."
local Policy = dofile(root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/issue_fixes/hero_ability_policy.lua")

local function hero(name, names, cascade)
    local unit = { abilities = {}, removed = {} }
    for _, abilityName in ipairs(names) do
        local ability = { name = abilityName, null = false }
        function ability:IsNull() return self.null end
        function ability:GetAbilityName()
            assert(not self.null, "must not access a removed native handle")
            return self.name
        end
        unit.abilities[#unit.abilities + 1] = ability
    end
    function unit:IsNull() return false end
    function unit:GetUnitName() return name end
    function unit:GetAbilityCount() return #self.abilities end
    function unit:GetAbilityByIndex(index) return self.abilities[index + 1] end
    function unit:FindAbilityByName(wanted)
        for _, ability in ipairs(self.abilities) do
            if ability.name == wanted then return ability end
        end
    end
    function unit:RemoveAbility(wanted)
        assert(self:FindAbilityByName(wanted), "only remove existing native abilities")
        self.removed[#self.removed + 1] = wanted
        for index = #self.abilities, 1, -1 do
            local ability = self.abilities[index]
            if ability.name == wanted or (cascade and cascade[wanted] and cascade[wanted][ability.name]) then
                ability.null = true
                table.remove(self.abilities, index)
            end
        end
    end
    return unit
end

local function preserves(unit, names)
    for _, name in ipairs(names) do
        assert(unit:FindAbilityByName(name), "must preserve " .. name)
    end
end

local morphCore = {
    "morphling_waveform", "morphling_adaptive_strike_agi", "morphling_adaptive_strike_str",
    "morphling_morph_agi", "morphling_morph_str", "morphling_ebb_and_flow",
    "morphling_accumulation", "morphling_ebb", "morphling_flow", "morphling_syntropy",
    "special_bonus_unique_morphling_8", "unrelated_replicate", "largo_amphibian_rhapsody",
}
local morphNames = { "morphling_replicate", "morphling_morph_replicate", "morphling_hybrid" }
for _, name in ipairs(morphCore) do morphNames[#morphNames + 1] = name end
local morph = hero("npc_dota_hero_morphling", morphNames)
assert(Policy.Apply(morph) == 3, "adjacent compacting slots must all be removed")
assert(not morph:FindAbilityByName("morphling_replicate"))
assert(not morph:FindAbilityByName("morphling_morph_replicate"))
assert(not morph:FindAbilityByName("morphling_hybrid"))
preserves(morph, morphCore)
assert(Policy.Apply(morph) == 0 and #morph.removed == 3, "repeat application must be safe")

local songs = { "largo_song_fight_song", "largo_song_double_time", "largo_song_good_vibrations" }
local largoCore = { "largo_catchy_lick", "largo_frogstomp", "largo_croak_of_genius", "largo_encore", "morphling_replicate" }
local largoNames = { "largo_amphibian_rhapsody" }
for _, name in ipairs(songs) do largoNames[#largoNames + 1] = name end
for _, name in ipairs(largoCore) do largoNames[#largoNames + 1] = name end
local largo = hero("npc_dota_hero_largo", largoNames)
assert(Policy.Apply(largo) == 4)
for _, name in ipairs(songs) do assert(not largo:FindAbilityByName(name)) end
assert(not largo:FindAbilityByName("largo_amphibian_rhapsody"))
preserves(largo, largoCore)
assert(Policy.Apply(largo) == 0)

local cascade = { largo_amphibian_rhapsody = {} }
for _, name in ipairs(songs) do cascade.largo_amphibian_rhapsody[name] = true end
local cascading = hero("npc_dota_hero_largo", largoNames, cascade)
assert(Policy.Apply(cascading) == 1, "native cascade must not cause stale subskill removal")
preserves(cascading, largoCore)
assert(Policy.Apply(cascading) == 0)

local sparse = hero("npc_dota_hero_largo", { "largo_catchy_lick", "largo_song_good_vibrations" })
sparse.abilities[24] = sparse.abilities[2]
sparse.abilities[2] = nil
function sparse:GetAbilityCount() return 32 end
function sparse:FindAbilityByName(name)
    for _, ability in pairs(self.abilities) do if ability.name == name then return ability end end
end
function sparse:RemoveAbility(name)
    assert(name == "largo_song_good_vibrations")
    self.abilities[24] = nil
end
assert(Policy.Apply(sparse) == 1, "hidden subskills beyond empty slots must be removed")
preserves(sparse, { "largo_catchy_lick" })
assert(Policy.Apply(sparse) == 0)

for _, name in ipairs({ "npc_dota_hero_arc_warden", "npc_dota_hero_rubick", "npc_dota_hero_largo_clone" }) do
    local normal = hero(name, { "arc_warden_tempest_double", "morphling_replicate", "largo_amphibian_rhapsody" })
    function normal:GetAbilityByIndex() error("unaffected heroes should not be scanned") end
    assert(Policy.Apply(normal) == 0 and #normal.removed == 0)
end
assert(Policy.Apply(nil) == 0)
assert(Policy.Apply({ IsNull = function() return true end }) == 0)
assert(Policy.Apply(hero("npc_dota_hero_morphling", morphCore)) == 0)
print("hero-ability-policy.test.lua: passed")
