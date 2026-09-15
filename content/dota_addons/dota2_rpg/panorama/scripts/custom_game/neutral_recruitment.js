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
            var row=$.CreatePanel("Panel",panel,"");row.AddClass("NeutralRecruitRow");
            var name=$.CreatePanel("Label",row,"");name.AddClass("NeutralRecruitSource");
            name.text=named("#DOTA_Tooltip_ability_"+source.source_name,source.source_name)+"  Lv."+source.source_level
                +(source.item_slot!==undefined ? " · "+text("item_slot")+" "+(Number(source.item_slot)+1) : "")
                +" · "+text("max_level")+(Number(source.max_level)>0 ? source.max_level : text("unlimited"))
                +(Number(source.max_count)>0 ? " · "+text("max_count")+source.max_count : "")+(source.allow_ancient===true || Number(source.allow_ancient)===1 ? " · "+text("ancient") : "");
            var select=$.CreatePanel("DropDown",row,"NeutralRecruitSelect"+index);select.AddClass("NeutralRecruitSelect");
            var options=[{unit_name:""}].concat(list(source.units)), selected="nr_"+index+"_0";
            options.forEach(function (unit,i) {
                var option=$.CreatePanel("Label",select,"nr_"+index+"_"+i);
                option.text=i===0 ? text("none") : named("#"+unit.unit_name,unit.unit_name.replace(/^npc_dota_neutral_/,"").replace(/_/g," "))
                    +" · Lv."+unit.level+(unit.ancient===true || Number(unit.ancient)===1 ? " · "+text("ancient") : "");
                select.AddOption(option);
                if (unit.unit_name===source.selected_unit) { selected=option.id; }
            });
            select.SetSelected(selected);
            select.enabled=phase==="setup" && hero.can_edit!==false && Number(hero.hero_index)>=0;
            select.SetPanelEvent("oninputsubmit",function () {
                var chosen=select.GetSelected(), match=chosen && /^nr_\d+_(\d+)$/.exec(chosen.id);
                var unit=match && options[Number(match[1])];
                if (!select.enabled || !unit) { return; }
                send({hero_entindex:Number(hero.hero_index),source_name:source.source_name,unit_name:unit.unit_name,
                    rule_generation:generation});
            });
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
