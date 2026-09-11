/* Last evaluated reason, not a claim of successful native execution. */
var RpgRuleDiagnostics=(function() {
    "use strict";
    var cache={},bindings=[],revision=0;
    function key(hero,heroKey,slot) { return hero+":"+heroKey+":"+slot; }
    function list(value) { return Array.isArray(value) ? value : Object.keys(value || {}).sort(function(a,b) { return Number(a)-Number(b); }).map(function(k) { return value[k]; }); }
    function message(reason) { return typeof RpgAbilityCapabilities!=="undefined" ? RpgAbilityCapabilities.message(reason) : reason; }
    function draw(binding) {
        var panel=binding.panel, data=cache[binding.key];
        if (panel.IsValid && !panel.IsValid()) { return; }
        if (data && data.action_id && binding.action && (data.action_id==="basic_attack" ? "attack" : data.action_id)!==binding.action) { data=null; }
        panel.text=data ? message(data.reason || data.event) : "";
        panel.SetHasClass("RuleDiagnosticWarning",!!data && data.event!=="rule_executed");
        var text=data ? "t="+Number(data.time).toFixed(2)+"  "+message(data.reason || data.event) : message("not_evaluated");
        if (data) {
            list(data.conditions).forEach(function(c) { text+="\n"+c.group+" #"+c.index+" "+c.type+" ["+(Number(c.passed)===1 ? "PASS" : "FAIL")+"] expected="+c.expected+" actual="+c.actual+" target="+c.target_index; });
            if (data.native_targets && data.native_targets.rejected!==undefined) { text+="\nnative targets accepted="+data.native_targets.accepted+" rejected="+data.native_targets.rejected; }
        }
        panel.SetPanelEvent("onmouseover",function() { $.DispatchEvent("DOTAShowTextTooltip",panel,text); });
        panel.SetPanelEvent("onmouseout",function() { $.DispatchEvent("DOTAHideTextTooltip",panel); });
    }
    function bind(panel,hero,heroKey,slot,action) {
        if (!panel) { return; }
        var binding=bindings.filter(function(b) { return b.panel===panel; })[0];
        if (!binding) { binding={panel:panel}; bindings.push(binding); }
        binding.key=key(hero,heroKey,slot); binding.action=action; draw(binding);
    }
    function receive(data) {
        if (!data || Number(data.revision)<revision) { return; }
        var k=key(data.hero_index,data.rule_key,data.slot); cache[k]=data;
        bindings.forEach(function(b) { if (b.key===k) { draw(b); } });
    }
    function reset(data) {
        revision=Number(data && data.revision || revision+1); cache={}; bindings.forEach(draw);
    }
    if (typeof GameEvents!=="undefined" && GameEvents.Subscribe) {
        GameEvents.Subscribe("rpg_rule_diagnostic",receive);
        GameEvents.Subscribe("rpg_rule_diagnostics_reset",reset);
    }
    return {bind:bind,receive:receive,reset:reset};
}());
