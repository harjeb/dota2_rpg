"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const {runHud,panel,click} = require("./condition-ui-v2.test");
const root=path.resolve(__dirname,"..");
const hud=runHud();
hud.context.Players.GetLocalPlayer=()=>0;
const timers=[];hud.context.$.Schedule=(delay,fn)=>timers.push(fn);
const p=id=>panel(hud,id);
const publish=patch=>hud.subscriptions.rpg_campaign_difficulty(Object.assign({owner_player_id:0,campaign_active:1,
    campaign_difficulty:"default",reward_multiplier:1,difficulty_locked:0},patch));
const selections=()=>hud.sentEvents.filter(e=>e.name==="rpg_campaign_difficulty_select");
assert(!p("CampaignDifficultyModal").visible,"wait for authoritative owner");
publish();assert(p("CampaignDifficultyModal").visible);
assert.deepStrictEqual(p("CampaignDifficultyCard").children.map(c=>c.id),["CampaignDifficultyChoices"],"entry contains only the difficulty choices");
assert.deepStrictEqual(p("CampaignDifficultyChoices").children.map(c=>c.id),["CampaignDifficulty_easy","CampaignDifficulty_default","CampaignDifficulty_hard"]);
click(hud,"CampaignDifficulty_easy");assert.strictEqual(selections().length,1,"one click selects and starts");
assert.strictEqual(selections()[0].payload.difficulty,"easy");
assert.deepStrictEqual(Object.keys(selections()[0].payload),["difficulty"],"client never sends multiplier or owner");
click(hud,"CampaignDifficulty_hard");assert.strictEqual(selections().length,1,"pending request blocks duplicate clicks");
publish();click(hud,"CampaignDifficulty_hard");assert.strictEqual(selections().length,1,"unlocked state refresh cannot release a pending request");
const staleTimer=timers[0]; staleTimer();
assert(p("CampaignDifficulty_hard").enabled,"lost response allows retry");
click(hud,"CampaignDifficulty_hard");assert.strictEqual(selections().length,2);
staleTimer();assert(!p("CampaignDifficulty_easy").enabled,"old timeout cannot release a newer request");
publish({campaign_difficulty:"hard",difficulty_locked:1});
assert(!p("CampaignDifficultyModal").visible);
click(hud,"CampaignDifficulty_easy");assert.strictEqual(selections().length,2,"locked choice is immutable");
publish({campaign_active:0});assert(!p("CampaignDifficultyModal").visible,"arena isolated");
publish({owner_player_id:1});assert(!p("CampaignDifficultyModal").visible && !p("CampaignDifficulty_easy").enabled);
// Reload/reconnect uses the authoritative server lock, with no stale local draft.
const script=fs.readFileSync(path.join(root,"content/dota_addons/dota2_rpg/panorama/scripts/custom_game/campaign_difficulty.js"),"utf8");
require("vm").runInContext(script,hud.context);
publish({campaign_difficulty:"easy",difficulty_locked:1});assert(!p("CampaignDifficultyModal").visible);
publish();click(hud,"CampaignDifficulty_default");assert.strictEqual(selections()[2].payload.difficulty,"default","Normal retains server difficulty ID");
const keys=[],versions=[];
for(const locale of ["english","schinese"]){
    const text=fs.readFileSync(path.join(root,"game/dota_addons/dota2_rpg/resource/addon_"+locale+".txt"),"utf8");
    const tokens=Object.fromEntries([...text.matchAll(/"(dota2_rpg_(?:difficulty_[^"]+|rank_difficulty_unranked|build_tag))"\s+"([^"]*)"/g)].map(m=>[m[1],m[2]]));
    const version=Number((tokens.dota2_rpg_build_tag.match(/(\d+)$/)||[])[1]);
    assert(version>=101); versions.push(version);
    keys.push(Object.keys(tokens).sort());
    assert.deepStrictEqual([tokens.dota2_rpg_difficulty_easy,tokens.dota2_rpg_difficulty_default,tokens.dota2_rpg_difficulty_hard],locale==="english" ? ["Easy","Normal","Hard"] : ["简单","普通","困难"]);
}
assert.deepStrictEqual(keys[0],keys[1]);
assert.strictEqual(versions[0],versions[1],"both locales must advertise the same build");
console.log("PASS campaign entry: only three choices, direct selection, duplicate/retry guards, owner/server locks, reconnect, matching bilingual UI101 labels");
