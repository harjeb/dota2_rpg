/* Server-derived ability contracts. This is UX validation, never authorization. */
var RpgAbilityCapabilities = (function () {
    "use strict";
    var heroes = Object.create(null);
    function own(object,key) { return object && Object.prototype.hasOwnProperty.call(object,key); }
    function clone(v) { return JSON.parse(JSON.stringify(v)); }
    function truth(v) { return v === true || v === 1 || v === "1" || v === "true"; }
    function present(v) { return v !== undefined && v !== null && v !== ""; }
    function list(v) { if (Array.isArray(v)) { return v; } return Object.keys(v || {}).sort(function(a,b) { return Number(a)-Number(b); }).map(function(k) { return v[k]; }); }
    function team(rule) { return rule.target_team || String(rule.target || "enemy").split("_")[0]; }
    function receive(event) {
        if (!event || !event.capability || Number(event.capability.version) !== 1 || Number(event.hero_index)<0) { return; }
        var key=String(event.hero_index), revision=Number(event.revision || 0), old=heroes[key];
        if (old && old.revision>revision) { return; }
        if (!old || old.revision!==revision || old.ruleKey!==event.rule_key) {
            old=heroes[key]={revision:revision,ruleKey:event.rule_key,actions:Object.create(null)};
        }
        old.actions[event.action_id]=event.capability;
    }
    function get(hero,action,key,revision) {
        var record=heroes[String(hero)];
        if (!record || record.ruleKey!==key || (revision!==undefined && record.revision!==Number(revision))) { return null; }
        if (own(record.actions,action)) { return record.actions[action]; }
        // Legacy slot names can become native names after an authoritative refresh.
        var matches=Object.keys(record.actions).filter(function(id) { return record.actions[id].name===action; });
        return matches.length===1 ? record.actions[matches[0]] : null;
    }
    function derive(base,rule) {
        if (!base) { return null; }
        var cap=clone(base), casts=cap.cast || {}, mode=cap.mode;
        var pref=rule.cast_preference || "auto";
        if (pref==="unit" && casts.unit===1 && casts.vector!==1 && casts.toggle!==1) { mode="unit"; }
        if (pref==="point" && casts.point===1 && casts.vector!==1 && casts.toggle!==1) { mode="point"; }
        if (present(rule.desired_autocast_state) && casts.autocast===1) { mode="autocast"; }
        var native=mode==="unit" || mode==="vector" && casts.unit===1 && casts.point!==1;
        if (native && cap.native_unit_contract) {
            ["teams","types","magic_immune_enemy","magic_immune_ally"].forEach(function(k) { cap[k]=cap.native_unit_contract[k]; });
        } else if (!native && cap.support!=="builtin") {
            cap.teams={self:1,ally:1,enemy:1}; cap.types={hero:1,monster:1,summon:1};
            cap.magic_immune_enemy=-1; cap.magic_immune_ally=-1;
        }
        cap.mode=mode; cap.role=native ? "native_unit" : mode==="point" || mode==="vector" ? "anchor" : "trigger";
        return cap;
    }
    function conditionReason(cap,group,c,targetTeam) {
        if (!cap) { return "capability_unavailable"; }
        var id=c.type || c.id || "";
        if (id.indexOf("tiny_grab_")===0 && cap.name!=="tiny_toss") { return "condition_requires_tiny_toss"; }
        if (id==="release_action_available" && !cap.release_parent) { return "condition_requires_release_action"; }
        var ownActor=!c.action_actor || c.action_actor==="self";
        var needsChannel=id==="channel_elapsed_gte" || id==="channel_elapsed_lte" || id==="action_phase_is" && c.value==="CHANNELING";
        if (needsChannel && ownActor) {
            if (!cap.release_parent) { return "channel_requires_release_or_other_actor"; }
            if (c.action_id && c.action_id!==cap.release_parent) { return "channel_reference_not_parent"; }
        }
        if (id==="action_phase_is" && c.value==="CASTING" && ownActor) { return "casting_phase_cannot_be_interrupted"; }
        if (group!=="target") { return ""; }
        if (id==="exclude_self" && targetTeam==="self") { return "self_excluded"; }
        if (id==="specified_enemy" && targetTeam!=="enemy") { return "invalid_specified_enemy_team"; }
        if (id==="is_spell_immune" && Number(targetTeam==="enemy" ? cap.magic_immune_enemy : cap.magic_immune_ally)===0) { return "condition_conflicts_with_native_targeting"; }
        return "";
    }
    function contradiction(rule) {
        var ranges={}, positive={}, negative={}, phases={}, error="", targetTeam=team(rule);
        [["use",rule.use_conditions],["target",rule.target_filters]].forEach(function(pair) {
            list(pair[1]).forEach(function(c) {
                if (!c || !c.type || error) { return; }
                var context=pair[0]==="target" && targetTeam==="self" ? "self" : pair[0], metric=c.type;
                if (pair[0]==="use" && metric.indexOf("self_")===0) { context="self"; metric=metric.substring(5); }
                var match=metric.match(/^(.*?)_(gte|lte|lt)$/), val=Number(c.seconds!==undefined ? c.seconds : c.value);
                var key=context+":"+(match ? match[1] : metric)+":"+(c.modifier || "")+":"+(c.action_id || "<current>")+":"+(c.action_actor || "self")+":"+(c.radius || "");
                if (match && isFinite(val)) {
                    var r=ranges[key] || {min:0,max:Infinity,strict:false};
                    if (match[2]==="gte") { r.min=Math.max(r.min,val); }
                    else if (val<r.max) { r.max=val; r.strict=match[2]==="lt"; }
                    else if (val===r.max && match[2]==="lt") { r.strict=true; }
                    ranges[key]=r;
                    if (r.min>r.max || r.min===r.max && r.strict) { error="contradictory_conditions"; }
                }
                if (metric==="action_phase_is") {
                    if (phases[key] && phases[key]!==c.value) { error="contradictory_conditions"; }
                    phases[key]=c.value;
                }
                var tag;
                if (metric==="has_modifier" || metric==="not_has_modifier") {
                    tag=context+":modifier:"+(c.modifier || c.value);
                    (metric==="has_modifier" ? positive : negative)[tag]=true;
                }
                if (metric==="is_spell_immune" || metric==="not_spell_immune") {
                    tag=context+":spell_immune"; (metric==="is_spell_immune" ? positive : negative)[tag]=true;
                }
                if (tag && positive[tag] && negative[tag]) { error="contradictory_conditions"; }
                if (pair[0]==="target" && targetTeam==="self") {
                    if (metric==="exclude_self") { error="self_excluded"; }
                    if (metric==="distance_gte" && val>0) { error="self_distance_must_be_zero"; }
                }
            });
        });
        var use=list(rule.use_conditions), ids={};
        use.forEach(function(c) { ids[c.type]=true; });
        if (ids.tiny_grab_is_ally && ids.tiny_grab_is_enemy) { error="contradictory_conditions"; }
        use.forEach(function(c) {
            if (c.type!=="no_enemy_within") { return; }
            use.forEach(function(n) { if (n.type==="nearby_enemies_gte" && Number(n.value)>0 && Number(n.radius || 600)<=Number(c.radius || c.value)) { error="contradictory_conditions"; } });
        });
        return error;
    }
    function validate(rule,base,options) {
        options=options || {};
        var cap=derive(base,rule), errors=[], warnings=[], targetTeam=team(rule);
        function fail(code,group,index,detail) { errors.push({code:code,group:group || "action",index:index || 0,detail:detail || ""}); }
        var bad=contradiction(rule); if (bad) { fail(bad); }
        if (!cap) { if (options.requireCapability) { fail("capability_unavailable"); } }
        else {
            if (cap.blocked_reason) { fail(cap.blocked_reason); }
            if ((cap.teams || {})[targetTeam]===0) { fail("target_team_incompatible"); }
            var types=Array.isArray(rule.target_types) ? rule.target_types : String(rule.target_types || "").split(",").filter(Boolean);
            if (types.length && !types.some(function(t) { return cap.types[t]!==0; })) { fail("target_types_incompatible"); }
            if (rule.cast_preference && cap.cast_preferences[rule.cast_preference]!==1) { fail("unsupported_cast_preference"); }
            if (present(rule.desired_toggle_state) && cap.cast.toggle!==1) { fail("toggle_not_supported"); }
            if (present(rule.desired_autocast_state) && cap.cast.autocast!==1) { fail("autocast_not_supported"); }
        }
        if (rule.cast_variant && rule.cast_variant!=="default") { fail("alternate_adapter_unavailable"); }
        if (rule.state_policy==="mana_hysteresis") {
            var on=Number(rule.state_mana_on), off=Number(rule.state_mana_off);
            if (!present(rule.state_mana_on) || !present(rule.state_mana_off) || !isFinite(on) || !isFinite(off) || off<0 || on>1 || off>=on) { fail("invalid_hysteresis_thresholds"); }
            if (cap && cap.cast.toggle!==1 && !(cap.cast.autocast===1 && present(rule.desired_autocast_state))) { fail("state_policy_requires_toggle_or_autocast"); }
        }
        [["use",rule.use_conditions],["target",rule.target_filters]].forEach(function(pair) {
            list(pair[1]).forEach(function(c,index) {
                if (!c || !c.type) { return; }
                var why=cap ? conditionReason(cap,pair[0],c,targetTeam) : "";
                if (why) { fail(why,pair[0],index+1); }
                var mod=c.modifier || (c.type.indexOf("has_modifier")>=0 ? c.value : "");
                if (mod) {
                    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(mod)) { fail("invalid_modifier_name",pair[0],index+1); }
                    else if (cap && !own(cap.modifiers,mod)) {
                        warnings.push({code:"modifier_not_observed",group:pair[0],index:index+1,detail:mod});
                        if (!truth(rule.allow_unverified_modifiers)) { fail("unverified_modifier_requires_ack",pair[0],index+1,mod); }
                    }
                }
            });
        });
        return {ok:!errors.length,errors:errors,warnings:warnings,capability:cap};
    }
    function message(code) {
        var raw=String(code || ""), base=raw.split(":")[0], token="#dota2_rpg_cap_"+base;
        var translated=typeof $!=="undefined" && $.Localize ? $.Localize(token) : token;
        return translated && translated!==token && translated!==token.substring(1) ? translated+(raw.indexOf(":")>=0 ? " ["+raw.substring(base.length+1)+"]" : "") : raw;
    }
    function describe(result) {
        return (result.errors || []).map(function(e) { return (e.index ? e.group+" #"+e.index+": " : "")+message(e.code)+(e.detail ? " ("+e.detail+")" : ""); }).join("\n");
    }
    if (typeof GameEvents!=="undefined" && GameEvents.Subscribe) { GameEvents.Subscribe("rpg_action_capability",receive); }
    return {receive:receive,get:get,derive:derive,validate:validate,contradiction:contradiction,conditionReason:conditionReason,message:message,describe:describe,team:team,truth:truth};
}());
