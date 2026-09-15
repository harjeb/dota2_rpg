var RpgNeutralRecruitment = (function () {
    function list(value) {
        if (Array.isArray(value)) { return value; }
        return Object.keys(value || {}).sort(function (a,b) { return Number(a)-Number(b); }).map(function (k) { return value[k]; });
    }
    function text(key) { return $.Localize("#dota2_rpg_neutral_" + key); }
    function named(token, fallback) { var value=$.Localize(token); return value===token ? fallback : value; }
    function render(panel, hero, phase, generation, send) {
        if (!panel) { return; }
        panel.RemoveAndDeleteChildren();
        var sources=list(hero && hero.neutral_recruitment);
        panel.visible=sources.length>0;
        if (!sources.length) { return; }
        var title=$.CreatePanel("Label",panel,"");title.text=text("title");title.AddClass("NeutralRecruitTitle");
        var hint=$.CreatePanel("Label",panel,"");hint.text=text("hint");hint.AddClass("NeutralRecruitHint");
        sources.forEach(function (source,index) {
            var multiple=source.source_name==="chen_holy_persuasion";
            var saved=multiple && source.selected_units!==undefined ? list(source.selected_units) : [source.selected_unit || ""];
            var slots=multiple ? Math.max(1,Math.min(32,Math.floor(Number(source.max_count)||0))) : 1;
            var row=$.CreatePanel("Panel",panel,"");row.AddClass("NeutralRecruitRow");
            var name=$.CreatePanel("Label",row,"");name.AddClass("NeutralRecruitSource");
            name.text=named("#DOTA_Tooltip_ability_"+source.source_name,source.source_name)+"  Lv."+source.source_level
                +(source.item_slot!==undefined ? " · "+text("item_slot")+" "+(Number(source.item_slot)+1) : "")
                +" · "+text("max_level")+(Number(source.max_level)>0 ? source.max_level : text("unlimited"))
                +(Number(source.max_count)>0 ? " · "+text("max_count")+source.max_count : "")
                +(multiple ? " · "+text("max_ancients")+(Number(source.max_ancients)||0)
                    : (source.allow_ancient===true || Number(source.allow_ancient)===1 ? " · "+text("ancient") : ""));
            var controls=[];
            function submit() {
                var choices=[];
                for (var j=0;j<controls.length;j++) {
                    var control=controls[j],chosen=control.select.GetSelected(),unit=chosen && control.byId[chosen.id];
                    if (!control.select.enabled || !unit) { return; }
                    if (unit.unit_name) { choices.push(unit.unit_name); }
                }
                var payload={hero_entindex:Number(hero.hero_index),source_name:source.source_name,rule_generation:generation};
                if (multiple) { payload.unit_names=choices; } else { payload.unit_name=choices[0] || ""; }
                send(payload);
            }
            for (var slot=0;slot<slots;slot++) {
                if (multiple) {
                    var slotLabel=$.CreatePanel("Label",row,"");slotLabel.AddClass("NeutralRecruitHint");slotLabel.text=text("slot")+" "+(slot+1);
                }
                var suffix=slot===0 ? String(index) : index+"_"+slot;
                var select=$.CreatePanel("DropDown",row,"NeutralRecruitSelect"+suffix);select.AddClass("NeutralRecruitSelect");
                var options=[{unit_name:""}].concat(list(source.units)), selected="nr_"+suffix+"_0",byId={};
                options.forEach(function (unit,i) {
                    var option=$.CreatePanel("Label",select,"nr_"+suffix+"_"+i);
                    option.text=i===0 ? text("none") : named("#"+unit.unit_name,unit.unit_name.replace(/^npc_dota_neutral_/,"").replace(/_/g," "))
                        +" · Lv."+unit.level+(unit.ancient===true || Number(unit.ancient)===1 ? " · "+text("ancient") : "");
                    select.AddOption(option);byId[option.id]=unit;
                    if (unit.unit_name===saved[slot]) { selected=option.id; }
                });
                select.SetSelected(selected);
                select.enabled=phase==="setup" && hero.can_edit!==false && Number(hero.hero_index)>=0;
                controls.push({select:select,byId:byId});
                select.SetPanelEvent("oninputsubmit",submit);
            }
        });
    }
    function result(panel,data,hero,generation) {
        if (!panel || !hero || Number(data.rule_generation)!==Number(generation)
            || Number(data.hero_entindex)!==Number(hero.hero_index)) { return; }
        var notice=panel.FindChildTraverse("NeutralRecruitNotice") || $.CreatePanel("Label",panel,"NeutralRecruitNotice");
        notice.AddClass("NeutralRecruitHint");
        notice.text=Number(data.success)===1 ? text("saved") : text("error");
    }
    return {render:render,result:result,list:list};
}());
