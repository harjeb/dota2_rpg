local RunState = {}
RunState.__index = RunState

function RunState.new()
    local seed = RandomInt(1, 2147483000)
    return setmetatable({
        run_seed = seed,
        stage = 1,
        phase = "PREPARE",
        gold = {},
        roster = {},
        active_lineup = {},
        warehouse = {},
        equipped_items = {},
        rules = {},
        stage_affixes = {},
        claimed_rewards = {},
        battle_units = {},
        unit_tags = {},
        row_tags = {},
    }, RunState)
end

function RunState:SetPhase(phase)
    assert(phase == "PREPARE" or phase == "COUNTDOWN" or phase == "FIGHT" or phase == "SETTLE")
    self.phase = phase
    CustomNetTables:SetTableValue("rpg_run", "summary", {
        stage = self.stage,
        phase = self.phase,
        run_seed = self.run_seed,
    })
end

function RunState:MarkRewardClaimed(stage)
    if self.claimed_rewards[stage] then
        return false
    end
    self.claimed_rewards[stage] = true
    return true
end

function RunState:ResetBattleUnits()
    self.battle_units = {}
    self.unit_tags = {}
    self.row_tags = {}
end

-- Intentionally no serialization, database, or cross-match persistence API.
return RunState
