const assert=require('assert'),fs=require('fs'),vm=require('vm');
class Panel {
 constructor(type,parent,id) {this.type=type;this.id=id;this.children=[];this.events={};this.enabled=true;if(parent)parent.children.push(this);}
 AddClass(){} RemoveAndDeleteChildren(){this.children=[];} AddOption(){}
 SetSelected(id){this.selected=id;} GetSelected(){return {id:this.selected};}
 SetPanelEvent(name,fn){this.events[name]=fn;}
 FindChildTraverse(id){for(const p of this.children){if(p.id===id)return p;const q=p.FindChildTraverse(id);if(q)return q;}}
}
const ctx={$:{Localize:s=>s,CreatePanel:(type,p,id)=>new Panel(type,p,id)}};
vm.createContext(ctx);vm.runInContext(fs.readFileSync('content/dota_addons/dota2_rpg/panorama/scripts/custom_game/neutral_recruitment.js','utf8'),ctx);
const ui=ctx.RpgNeutralRecruitment,panel=new Panel(),sent=[];
const hero={hero_index:42,can_edit:true,neutral_recruitment:{'1':{source_name:'enchantress_enchant',source_level:2,max_level:4,max_count:2,allow_ancient:false,
 selected_unit:'npc_dota_neutral_centaur_khan',units:{'1':{unit_name:'npc_dota_neutral_centaur_khan',level:4,ancient:false},'2':{unit_name:'npc_dota_neutral_satyr_trickster',level:2,ancient:false}}}}};
ui.render(panel,hero,'setup',7,p=>sent.push(p));assert(panel.visible);
let select=panel.FindChildTraverse('NeutralRecruitSelect0');assert.equal(select.selected,'nr_0_1');assert.equal(sent.length,0,'render must not submit defaults');
select.SetSelected('nr_0_2');select.events.oninputsubmit();
assert.equal(sent[0].unit_name,'npc_dota_neutral_satyr_trickster');assert.equal(sent[0].hero_entindex,42);assert.equal(sent[0].rule_generation,7);
select.SetSelected('nr_0_0');select.events.oninputsubmit();assert.equal(sent[1].unit_name,'','clear selection');
ui.render(panel,hero,'fight',7,p=>sent.push(p));select=panel.FindChildTraverse('NeutralRecruitSelect0');assert.equal(select.enabled,false);select.events.oninputsubmit();assert.equal(sent.length,2);
ui.result(panel,{hero_entindex:99,rule_generation:7,success:1},hero,7);assert(!panel.FindChildTraverse('NeutralRecruitNotice'));
ui.result(panel,{hero_entindex:42,rule_generation:6,success:1},hero,7);assert(!panel.FindChildTraverse('NeutralRecruitNotice'));
ui.result(panel,{hero_entindex:42,rule_generation:7,success:1},hero,7);assert(panel.FindChildTraverse('NeutralRecruitNotice').text.endsWith('_saved'));
ui.render(panel,{hero_index:43,neutral_recruitment:[]},'setup',7,()=>{});assert.equal(panel.visible,false);assert.equal(panel.children.length,0);
const layout=fs.readFileSync('content/dota_addons/dota2_rpg/panorama/layout/custom_game/rpg_demo_hud.xml','utf8');
assert(layout.indexOf('neutral_recruitment.js')<layout.indexOf('rpg_demo_hud.js'));assert(layout.includes('id="NeutralRecruitment"'));
const chen=JSON.parse(JSON.stringify(hero));const source=chen.neutral_recruitment['1'];
source.source_name='chen_holy_persuasion';source.max_count=4;source.max_ancients=1;
source.selected_units={'1':'npc_dota_neutral_centaur_khan','2':'npc_dota_neutral_satyr_trickster'};
ui.render(panel,chen,'setup',8,p=>sent.push(p));
assert.equal(panel.FindChildTraverse('NeutralRecruitSelect0').selected,'nr_0_1');
assert.equal(panel.FindChildTraverse('NeutralRecruitSelect0_1').selected,'nr_0_1_2');
assert(panel.FindChildTraverse('NeutralRecruitSelect0_3'),'one choice per live control slot');
let third=panel.FindChildTraverse('NeutralRecruitSelect0_2');third.SetSelected('nr_0_2_1');third.events.oninputsubmit();
assert.deepEqual(Array.from(sent[sent.length-1].unit_names),['npc_dota_neutral_centaur_khan','npc_dota_neutral_satyr_trickster','npc_dota_neutral_centaur_khan'],'complete list permits repeated species');
assert(!('unit_name' in sent[sent.length-1]),'Chen sends list not scalar');
for(const id of ['NeutralRecruitSelect0','NeutralRecruitSelect0_1','NeutralRecruitSelect0_2','NeutralRecruitSelect0_3']) {
 const dropdown=panel.FindChildTraverse(id);dropdown.SetSelected(dropdown.children[0].id);
}
third.events.oninputsubmit();assert.equal(sent[sent.length-1].unit_names.length,0,'clear all sends empty list');
source.max_count=1;source.selected_units=['npc_dota_neutral_satyr_trickster'];
ui.render(panel,chen,'setup',8,p=>sent.push(p));assert(!panel.FindChildTraverse('NeutralRecruitSelect0_1'),'live cap reduction removes extra slots');
assert.equal(panel.FindChildTraverse('NeutralRecruitSelect0').selected,'nr_0_2');
console.log('PASS neutral recruitment UI: eligibility, Chen multiple/repeated choices, full-list clearing, live caps, fight lock and stale results');
