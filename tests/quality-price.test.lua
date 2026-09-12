-- 品质溢价回归：精良/史诗/传说的购入价必须高于同等级普通英雄。
-- 旧 DESIGN.md 的品质倍率表为 普通 1.0 / 精良 1.2 / 史诗 1.5 / 传说 2.0；
-- 提交 1d29289 曾把"品质不影响售价"写进文档并让 PriceFor 忽略品质，
-- 表现就是高品质英雄和普通英雄同价。本测试锁住倍率，防止再次退化。
local root = TEST_REPO_ROOT or "."
local moduleRoot = root .. "/game/dota_addons/dota2_rpg/scripts/vscripts/"

local ProgressionData = dofile(moduleRoot .. "data/progression_data.lua")

-- 1) 倍率表必须完整且与文档一致
local expected = { common = 1.0, fine = 1.2, epic = 1.5, legendary = 2.0 }
for quality, multiplier in pairs(expected) do
    assert(ProgressionData.QUALITY_PRICE_MULTIPLIER[quality] == multiplier,
        "quality multiplier mismatch for " .. quality)
end

-- 2) 每个招募等级：普通 < 精良 < 史诗 < 传说，且都是整数
for _, band in ipairs(ProgressionData.RECRUIT_BANDS) do
    local common = ProgressionData.PriceFor(band.level, "common")
    local fine = ProgressionData.PriceFor(band.level, "fine")
    local epic = ProgressionData.PriceFor(band.level, "epic")
    local legendary = ProgressionData.PriceFor(band.level, "legendary")
    for quality, price in pairs({ common = common, fine = fine, epic = epic, legendary = legendary }) do
        assert(type(price) == "number", "price must exist for level " .. band.level .. " " .. quality)
        assert(price == math.floor(price), "price must be integral: level " .. band.level .. " " .. quality)
    end
    assert(common == band.price, "common price must equal the band base price")
    assert(fine > common, "fine must cost more than common at level " .. band.level
        .. " (common=" .. common .. " fine=" .. fine .. ")")
    assert(epic > fine, "epic must cost more than fine at level " .. band.level
        .. " (fine=" .. fine .. " epic=" .. epic .. ")")
    assert(legendary > epic, "legendary must cost more than epic at level " .. band.level
        .. " (epic=" .. epic .. " legendary=" .. legendary .. ")")
end

-- 3) 具体数值抽查（与 DESIGN.md 的倍率一致）
assert(ProgressionData.PriceFor(1, "common") == 500)
assert(ProgressionData.PriceFor(1, "fine") == 600)
assert(ProgressionData.PriceFor(1, "epic") == 750)
assert(ProgressionData.PriceFor(1, "legendary") == 1000)
assert(ProgressionData.PriceFor(10, "epic") == 2400)
assert(ProgressionData.PriceFor(24, "legendary") == 11000)

-- 4) 缺失/未知品质按普通处理，不能返回 nil 或抛错
assert(ProgressionData.QualityMultiplier(nil) == 1.0)
assert(ProgressionData.QualityMultiplier("nonexistent") == 1.0)
assert(ProgressionData.PriceFor(1, nil) == 500)
assert(ProgressionData.PriceFor(1) == 500)

-- 5) 未知等级仍然返回 nil，让调用方走自己的兜底
assert(ProgressionData.PriceFor(999, "epic") == nil)

print("PASS: quality price multipliers (fine/epic/legendary cost more than common)")
