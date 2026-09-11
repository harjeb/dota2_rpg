/* Layout/protocol fixture, NOT a native-ability truth database.
 * Each legacy UI test now receives the server capability events required by the
 * real layout. Native contract correctness is tested independently in the matrix.
 */
"use strict";
exports.attach = function (context, subscriptions) {
    var slots = subscriptions.rpg_hero_slots, revision = 0;
    subscriptions.rpg_hero_slots = function (data) {
        var d = Object.assign({}, data), rev=++revision;
        var key=d.rule_key || String(d.hero_name || "")+":"+d.slot_key;
        String(d.actions_text || "").split(";").filter(Boolean).forEach(function (id,index) {
            var name=String(d.details_text || "").split(";")[index] || id;
            var builtin=id==="attack" || id==="move" || id==="sustained_move";
            var heal=name==="omniknight_purification";
            var teams=heal ? {self:1,ally:1,enemy:0} : {self:1,ally:1,enemy:1};
            var cap={version:1,name:name,mode:builtin ? "attack" : heal ? "unit" : "point",
                role:heal ? "native_unit" : builtin ? "trigger" : "anchor",
                support:builtin ? "builtin" : "generic",teams:teams,
                types:{hero:1,monster:1,summon:1},cast:{unit:builtin ? 0:1,point:!builtin&&!heal ? 1:0,none:0,toggle:0,autocast:0,vector:0},
                cast_preferences:{auto:1,unit:builtin ? 0:1,point:!builtin&&!heal ? 1:0},
                variants:{default:1,alternate:0},
                modifiers:{modifier_test:1},release_parent:"",magic_immune_enemy:-1,magic_immune_ally:-1};
            cap.native_unit_contract={teams:teams,types:cap.types,magic_immune_enemy:-1,magic_immune_ally:-1};
            context.RpgAbilityCapabilities.receive({hero_index:d.hero_index,rule_key:key,revision:rev,action_id:id,capability:cap});
        });
        d.capability_revision=rev; slots(d);
    };
};
