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
assert(p("CampaignDifficulty_default").BHasClass("CampaignDifficultySelected"));
click(hud,"CampaignDifficulty_easy");
publish();assert(p("CampaignDifficulty_easy").BHasClass("CampaignDifficultySelected"),"state refresh cannot erase unconfirmed draft");
click(hud,"CampaignDifficultyConfirm");assert.strictEqual(selections().length,1);
assert.strictEqual(selections()[0].payload.difficulty,"easy");
assert.deepStrictEqual(Object.keys(selections()[0].payload),["difficulty"],"client never sends multiplier or owner");
click(hud,"CampaignDifficultyConfirm");assert.strictEqual(selections().length,1);
publish({campaign_difficulty:"easy",reward_multiplier:1.5,difficulty_locked:1});
assert(!p("CampaignDifficultyModal").visible);assert(p("CampaignDifficultyBadge").text.includes("1.5"));
click(hud,"CampaignDifficulty_hard");assert.strictEqual(selections().length,1);
publish({campaign_difficulty:"easy",reward_multiplier:1.5,difficulty_locked:1});
assert(p("CampaignDifficulty_easy").BHasClass("CampaignDifficultySelected"),"reconnect retains server selection");
publish({campaign_active:0});assert(!p("CampaignDifficultyModal").visible && !p("CampaignDifficultyBadge").visible,"arena isolated");
publish({owner_player_id:1});assert(!p("CampaignDifficultyModal").visible && !p("CampaignDifficultyConfirm").enabled);
// Panorama reload retains the local draft before confirmation via context panel.
publish();click(hud,"CampaignDifficulty_hard");
const script=fs.readFileSync(path.join(root,"content/dota_addons/dota2_rpg/panorama/scripts/custom_game/campaign_difficulty.js"),"utf8");
require("vm").runInContext(script,hud.context);publish();
assert(p("CampaignDifficulty_hard").BHasClass("CampaignDifficultySelected"));
const keys=[],versions=[];
for(const locale of ["english","schinese"]){
    const text=fs.readFileSync(path.join(root,"game/dota_addons/dota2_rpg/resource/addon_"+locale+".txt"),"utf8");
    const tokens=Object.fromEntries([...text.matchAll(/"(dota2_rpg_(?:difficulty_[^"]+|rank_difficulty_unranked|build_tag))"\s+"([^"]*)"/g)].map(m=>[m[1],m[2]]));
    const version=Number((tokens.dota2_rpg_build_tag.match(/(\d+)$/)||[])[1]);
    assert(version>=79); versions.push(version);
    keys.push(Object.keys(tokens).sort());
    for(const name of ["easy","default","hard","title","hint","ranking","confirm","rewards"]){assert(tokens["dota2_rpg_difficulty_"+name]);}
}
assert.deepStrictEqual(keys[0],keys[1]);
assert.strictEqual(versions[0],versions[1],"both locales must advertise the same build");
console.log("PASS campaign entry difficulty: actual XML scripts, owner gates, default selection, draft refresh/reload persistence, immutable server selection, arena isolation, matching bilingual build versions");
