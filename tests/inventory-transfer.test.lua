-- Run the compatibility service and actual OnItemEquip integration under the
-- standard suite. Its native inventory mocks distinguish TakeItem from deletion.
local root = TEST_REPO_ROOT or "."
arg = { root .. "/dota2_rpg_issue_fixes", "live" }
dofile(root .. "/dota2_rpg_issue_fixes/tests/test_runtime.lua")
