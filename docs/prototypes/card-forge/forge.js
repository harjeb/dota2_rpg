(function () {
  "use strict";
  const M = window.CardForge, $ = id => document.getElementById(id);
  let state = M.initial(), selected = "H-lina", faction = "all", type = "all", query = "", descending = true;
  let history = [], dragged = null, toastTimer, modalMode = "", focusBeforeModal;
  const types = {hero: "英雄专属", buff: "增益卡", charge: "消耗卡", field: "场地卡"};
  const heroName = id => (M.heroes.find(h => h.id === id) || {}).name || "未知英雄";
  const art = card => `assets/${card.art}.png`;
  const back = f => `../../../pics/${M.factions[f].back}`;
  const style = f => `--faction:${M.factions[f].color};--back:url('${back(f)}')`;
  const escape = text => String(text).replace(/[&<>"']/g, char => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[char]));
  function notify(text, error = false) {
    clearTimeout(toastTimer); $("toast").textContent = text; $("toast").className = `toast visible${error ? " error" : ""}`;
    toastTimer = setTimeout(() => $("toast").className = "toast", 3600);
  }
  function cardHTML(card, detail = false) {
    const f = M.factions[card.faction], badge = card.plus ? `加值 +${card.plus}` : card.type === "hero" ? "专属契约" : "";
    return `<button class="relic-card ${selected === card.id && !detail ? "selected" : ""}" style="${style(card.faction)}" data-card="${card.id}" draggable="${!detail && state.phase === "prepare"}" aria-label="${card.name}，${types[card.type]}，拥有等级 ${card.level}，装载等级 ${card.load}，COST ${M.cost(card)}" ${detail ? 'tabindex="-1"' : `aria-pressed="${selected === card.id}"`}>
      <span class="card-art"><img src="${art(card)}" alt="" draggable="false" data-fallback="${back(card.faction)}"></span><span class="card-cost" title="装载 COST">${M.cost(card)}</span><span class="card-faction">${f.glyph}</span>
      <span class="card-copy"><span class="card-name">${card.name}</span><span class="card-type">${f.name} · ${types[card.type]}</span><span class="card-level" title="拥有等级 ${card.level}">${"◆".repeat(card.level)}<span class="locked">${"◇".repeat(3-card.level)}</span></span></span>${badge ? `<span class="card-badge">${badge}</span>` : ""}</button>`;
  }
  function bindFallbacks() {
    document.querySelectorAll("img[data-fallback]").forEach(img => {
      img.onerror = () => { img.onerror = null; img.src = img.dataset.fallback; img.classList.add("asset-fallback"); };
    });
  }
  function execute(action, message) {
    const result = M.apply(state, action);
    if (result.error) { notify(result.error, true); return false; }
    if (!["buy", "exchange", "smelt", "confirm", "return"].includes(action.type)) {
      history.push(state); if (history.length > 30) history.shift();
    } else history = [];
    state = result.state; render(); if (message) notify(message); return true;
  }
  function render() {
    const count = M.inventory(state).length, used = M.used(state), max = M.budget(state);
    $("capacity").textContent = count; $("gold").textContent = state.gold.toLocaleString();
    $("offer-count").textContent = `剩余购买 ${3-state.purchases} / 3`;
    $("cost").innerHTML = `${used} <small>/ ${max}</small>`;
    $("budget-fill").style.width = `${Math.min(100, used / max * 100)}%`;
    document.querySelector(".budget").classList.toggle("over", used > max);
    $("cost-hint").textContent = used > max ? `超出 ${used-max} · 降低装载等级或卸卡` : `还可使用 ${max-used} COST`;
    $("confirm").disabled = used > max || state.phase !== "prepare";
    $("confirm").innerHTML = state.phase !== "prepare" ? "构筑已锁定" : used > max ? "COST 超出预算" : "确认构筑 <span>⟶</span>";
    $("undo").disabled = !history.length || state.phase !== "prepare";
    document.body.classList.toggle("card-locked", state.phase !== "prepare");
    $("faction-ledger").innerHTML = Object.entries(M.factions).map(([key,f]) => `<div class="ledger-row" style="--faction:${f.color}"><span class="sigil">${f.glyph}</span><span>${f.name}</span><b>${state.points[key]}</b></div>`).join("");
    $("faction-tabs").innerHTML = `<button class="faction-tab ${faction === "all" ? "active" : ""}" data-faction="all" aria-pressed="${faction === "all"}">全部</button>` + Object.entries(M.factions).map(([key,f]) => `<button class="faction-tab ${faction === key ? "active" : ""}" style="--faction:${f.color}" data-faction="${key}" aria-pressed="${faction === key}"><span>${f.glyph}</span>${f.name}</button>`).join("");
    renderGrid(); renderInspector(); renderRoster(); bindFallbacks();
  }
  function renderGrid() {
    const cards = M.inventory(state).filter(c => (faction === "all" || c.faction === faction) && (type === "all" || c.type === type) && `${c.name} ${c.theme} ${M.factions[c.faction].name}`.includes(query));
    cards.sort((a,b) => (descending ? b.level-a.level : a.level-b.level) || a.id.localeCompare(b.id));
    $("card-grid").innerHTML = cards.map(c => cardHTML(c)).join("");
    $("empty").hidden = cards.length !== 0; $("visible-count").textContent = `${cards.length} 张遗物`;
  }
  function renderInspector() {
    const card = M.get(state, selected);
    if (!card) { $("inspector").innerHTML = '<div class="empty-state"><span>✧</span><h3>聆听遗物的回响</h3><p>选择卡牌查看详情与装载等级。</p></div>'; return; }
    const loc = M.location(state, card.id), locked = state.phase !== "prepare";
    const behavior = card.type === "charge" ? `本场 ${card.load} 次 · 战后恢复次数` : card.type === "field" ? "场地跟随携带者 · 阵亡后消散" : "本场战斗生效 · 战后清除";
    $("inspector").innerHTML = `<div class="inspector-top"><span>遗物详解</span><span>${card.id}</span></div><div class="showcase">${cardHTML(card,true)}</div>
      <div class="detail-heading"><h3>${card.name}</h3><p>${card.theme}</p></div><div class="detail-rule"></div>
      <div class="detail-info"><p><strong>${card.hero ? `仅限 ${heroName(card.hero)} · 专属槽` : "任意英雄 · 通用槽"}</strong></p><p>作用于所有合法友方</p><p>${behavior}</p><p class="flavor">${card.type === "hero" ? "「以英雄之名，缔结全队的契约。」" : "「远古的力量，在新的羁绊中苏醒。」"}</p></div>
      <div class="level-label">本场装载等级 <span>拥有 Lv.${card.level} · ${Math.min(3,card.copies)}/3</span></div><div class="level-picker">${[1,2,3].map(level => `<button class="${card.load===level?"active":""}" data-level="${level}" aria-label="装载等级 ${level}，COST ${M.curves[card.tier][level-1]}" aria-pressed="${card.load===level}" ${level>card.level || locked?"disabled":""}>Lv.${level}<small>${M.curves[card.tier][level-1]} COST</small></button>`).join("")}</div>
      <div class="detail-actions"><button class="metal-button" id="detail-equip" ${locked?"disabled":""}>${loc?"卸回卡库":"选择装备位置"}</button>${card.type==="hero"?`<button class="quiet-button" id="detail-smelt" ${loc||locked?"disabled":""} title="仅未装备专属卡可以熔炼">熔炼</button>`:""}</div>
      <p class="subtle-note">${loc?`已装备：${heroName(loc.split(":")[0])} · 不占卡库容量` : "拖拽至下方亮起的槽位，或点击槽位装备。"}<br>效果与 COST 分档为演示，正式效果待设计。</p>`;
    $("inspector").querySelectorAll("[data-level]").forEach(button => button.onclick = () => execute({type:"level",id:selected,level:Number(button.dataset.level)}, "装载等级已调整"));
    $("detail-equip").onclick = () => loc ? execute({type:"unequip",id:selected}, "遗物已退回卡库") : notify("点击下方亮起的槽位完成装备");
    if ($("detail-smelt")) $("detail-smelt").onclick = () => showSmelt(card.id);
  }
  function renderRoster() {
    $("hero-roster").innerHTML = state.heroes.map(h => `<div class="hero-unit" style="--faction:${M.factions[h.faction].color}"><div class="hero-portrait"><img src="assets/${h.id}.png" alt="" data-fallback="${back(h.faction)}"><span class="hero-name">${h.name}</span><span class="hero-lv">Lv.${h.level}</span></div><div class="hero-slots">${["hero","general"].map(kind => {
      const key = `${h.id}:${kind}`, card = M.get(state,state.slots[key]);
      return `<button class="slot ${card?"filled":""} ${card&&card.id===selected?"selected":""}" data-slot="${key}" ${card?`data-equipped="${card.id}" draggable="${state.phase==="prepare"}"`:""} aria-label="${h.name}${kind==="hero"?"专属槽":"通用槽"}${card?`，${card.name}，装载等级 ${card.load}`:"，空"}">${card?`<img src="${art(card)}" alt="" draggable="false" data-fallback="${back(card.faction)}"><span class="slot-title">${card.name}</span><small>Lv.${card.load} · ${M.cost(card)} COST</small>`:`<span class="slot-icon">${kind==="hero"?"♜":"✧"}</span>${kind==="hero"?"专属槽":"通用槽"}`}</button>`;
    }).join("")}</div></div>`).join("");
    highlightSlots(selected);
  }
  function highlightSlots(id) {
    document.querySelectorAll("[data-slot]").forEach(el => {
      const active = id && M.get(state,id) && state.phase === "prepare", allowed = active && !M.eligibility(state,id,el.dataset.slot);
      el.classList.toggle("eligible",!!allowed); el.classList.toggle("ineligible",!!active&&!allowed);
    });
  }
  function previewSlot(key) {
    const id = dragged || selected;
    if (!id) return;
    const error = M.eligibility(state,id,key);
    if (error) { $("inventory-hint").textContent = error; return; }
    const preview = M.apply(state,{type:"equip",id,slot:key});
    if (preview.error) { $("inventory-hint").textContent=preview.error; return; }
    const cost = M.used(preview.state), old = M.get(state,state.slots[key]);
    $("inventory-hint").textContent = `${heroName(key.split(":")[0])} · ${old?`替换「${old.name}」并退回卡库` : "装备遗物"} · COST ${M.used(state)} → ${cost}${cost>M.budget(state)?" · 超出预算，需调整":""}`;
  }
  function select(id) { selected = id; render(); }
  $("card-grid").onclick = event => { const el=event.target.closest("[data-card]"); if(el) select(el.dataset.card); };
  $("faction-tabs").onclick = event => { const el=event.target.closest("[data-faction]"); if(el){ faction=el.dataset.faction;render(); } };
  $("search").oninput = event => { query=event.target.value.trim();renderGrid();bindFallbacks(); };
  $("type-filter").onchange = event => {type=event.target.value;renderGrid();bindFallbacks();};
  $("sort").onclick = () => { descending=!descending;$("sort").textContent=descending?"等级 ↓":"等级 ↑";renderGrid();bindFallbacks(); };
  $("clear-filter").onclick = () => {faction="all";type="all";query="";$("search").value="";$("type-filter").value="all";render();};
  $("hero-roster").onclick = event => {
    const slot=event.target.closest("[data-slot]");if(!slot)return;
    if(state.phase!=="prepare"){notify("构筑已锁定，请先返回准备",true);return;}
    if(selected && M.get(state,selected) && state.slots[slot.dataset.slot]!==selected) {
      execute({type:"equip",id:selected,slot:slot.dataset.slot},"契约已缔结 · 全队共享遗物力量");
    } else if(slot.dataset.equipped) select(slot.dataset.equipped);
  };
  $("hero-roster").oncontextmenu = event => {const el=event.target.closest("[data-equipped]");if(el){event.preventDefault();select(el.dataset.equipped);}};
  $("hero-roster").onmouseover = event => {const el=event.target.closest("[data-slot]");if(el)previewSlot(el.dataset.slot);};
  $("hero-roster").onmouseout = () => $("inventory-hint").textContent="拖拽卡牌至英雄槽位 · 拖回此处卸下";
  document.addEventListener("dragstart",event => {
    const el=event.target.closest("[data-card],[data-equipped]");if(!el)return;
    if(state.phase!=="prepare" || el.closest(".showcase")){event.preventDefault();return;}
    dragged=el.dataset.card||el.dataset.equipped;selected=dragged;
    event.dataTransfer.setData("text/plain",dragged);event.dataTransfer.effectAllowed="move";
    document.body.classList.add("dragging");highlightSlots(dragged);
  });
  document.addEventListener("dragend",() => {dragged=null;document.body.classList.remove("dragging");document.querySelectorAll(".drop-hover,.drop-invalid").forEach(el=>el.classList.remove("drop-hover","drop-invalid"));render();});
  document.addEventListener("dragover",event => {
    if(!dragged)return;const slot=event.target.closest("[data-slot]");
    if(slot){event.preventDefault();const error=M.eligibility(state,dragged,slot.dataset.slot);slot.classList.toggle("drop-hover",!error);slot.classList.toggle("drop-invalid",!!error);event.dataTransfer.dropEffect=error?"none":"move";previewSlot(slot.dataset.slot);}
    else if(event.target.closest("#inventory")){event.preventDefault();$("inventory").classList.add("drop-hover");}
  });
  document.addEventListener("dragleave",event => {const el=event.target.closest("[data-slot],#inventory");if(el&&!el.contains(event.relatedTarget))el.classList.remove("drop-hover","drop-invalid");});
  document.addEventListener("drop",event => {
    if(!dragged)return;event.preventDefault();const slot=event.target.closest("[data-slot]");
    if(slot)execute({type:"equip",id:dragged,slot:slot.dataset.slot},"遗物已装备");
    else if(event.target.closest("#inventory")&&M.location(state,dragged))execute({type:"unequip",id:dragged},"遗物已退回卡库");
    dragged=null;$("inventory").classList.remove("drop-hover");
  });
  $("undo").onclick=()=>{if(history.length&&state.phase==="prepare"){state=history.pop();render();notify("已撤销上一步配装操作");}};
  function openModal(html, mode) {focusBeforeModal=document.activeElement;modalMode=mode;$("modal-content").innerHTML=html;if(!$("modal").open)$("modal").showModal();bindFallbacks();}
  function closeModal(){ $("modal").close();modalMode="";document.querySelectorAll(".nav-item").forEach(b=>b.classList.toggle("active",b.id==="library-nav"));if(focusBeforeModal&&focusBeforeModal.isConnected)focusBeforeModal.focus(); }
  $("modal-close").onclick=closeModal;$("modal").addEventListener("cancel",event=>{event.preventDefault();closeModal();});
  $("modal").addEventListener("click",event=>{if(event.target===$("modal"))closeModal();});
  $("library-nav").onclick=()=>{if($("modal").open)closeModal();$("search").focus();};
  $("help").onclick=()=>openModal(`<div class="modal-heading"><span class="eyebrow">THE ART OF THE BUILD</span><h2>缔结你的契约</h2><p>英雄提供位置，遗物构筑全队的战斗方式。</p></div><div class="help-grid"><section><h3>01 · 拖拽，或点选</h3><p>将卡牌拖至下方亮起的槽位。也可先点卡牌，再点槽位。无效位置会提示原因；释放到空白处取消。</p></section><section><h3>02 · 两种槽位</h3><p>专属卡只属于对应英雄的专属槽。基础卡放入任意英雄通用槽，同一张卡只能占据一个位置。</p></section><section><h3>03 · 管理装载</h3><p>右侧选择 Lv.1～Lv.3。拥有等级决定可用档位，装载等级决定本场 COST。超预算会阻止确认，不会擅自卸卡。</p></section><section><h3>04 · 整理秘库</h3><p>将已装备卡拖回大包裹即可卸下。右键槽位查看已装备卡。装备中不占 24 张容量。满仓处理暂以保留资产、阻止退卡演示。</p></section></div><p class="subtle-note">本页为独立交互原型：演示资源、卡名与数值不代表正式效果；熔炼及购买只影响本页。刷新页面重新开始。</p>`,"help");
  function showOffers() {
    document.querySelectorAll(".nav-item").forEach(b=>b.classList.toggle("active",b.id==="offer-nav"));
    openModal(`<div class="modal-heading"><span class="eyebrow">A PACT WITH FATE</span><h2>命运召唤</h2><p>五道封印，等待你的选择。<br>本波剩余购买 <strong>${3-state.purchases} / 3</strong> · 金币 <strong>${state.gold}</strong> · 与英雄招募共用次数</p></div><div class="offers">${state.offers.map((id,index)=>{
      const c=M.definitions.find(c=>c.id===id),bought=state.bought.includes(index);
      return `<div class="offer ${bought?"revealed":""}">${bought?cardHTML(M.get(state,id),true):`<div class="offer-back"><img src="${back(c.faction)}" alt="${M.factions[c.faction].name}阵营卡背"><span class="offer-seal">${M.factions[c.faction].name} · ${types[c.type]}</span></div>`}<button class="metal-button" data-buy="${index}" ${bought||state.purchases>=3||state.gold<100||state.phase!=="prepare"?"disabled":""}>${bought?"已揭晓":"◈ 100 · 揭开封印"}</button></div>`;
    }).join("")}</div><p class="offer-note">购买前只显示阵营与类型 · 重复卡自动累计拥有等级 · 不会自动提高装载等级</p>`,"offers");
    $("modal-content").querySelectorAll("[data-buy]").forEach(b=>b.onclick=()=>{if(execute({type:"buy",index:Number(b.dataset.buy)},"封印已开启 · 遗物收入秘库"))showOffers();});
  }
  $("offer-nav").onclick=showOffers;
  function showForge(){
    document.querySelectorAll(".nav-item").forEach(b=>b.classList.toggle("active",b.id==="forge-nav"));
    const smeltable=M.inventory(state).filter(c=>c.type==="hero");
    openModal(`<div class="modal-heading"><span class="eyebrow">THE FACTION FORGE</span><h2>阵营熔炉</h2><p>熔炼 1 份专属卡，获得 1 点同阵营印记。3 点印记可兑换 1 份同阵营基础卡。</p></div><div class="forge-layout"><section><h3>熔炼专属契约</h3><div class="forge-list">${smeltable.map(c=>`<div class="forge-row"><img src="${art(c)}" alt=""><div>${c.name}<small>${M.factions[c.faction].name} · 拥有 ${c.copies} 份 · Lv.${c.level}</small></div><button class="metal-button" data-smelt="${c.id}">熔炼</button></div>`).join("")||'<p class="subtle-note">没有可熔炼的未装备专属卡。</p>'}</div></section><section><h3>兑换基础遗物</h3><div class="forge-list">${M.definitions.filter(c=>c.type!=="hero").map(c=>`<div class="forge-row"><img src="${art(c)}" alt=""><div>${c.name}<small>${M.factions[c.faction].name}印记 ${state.points[c.faction]} / 3</small></div><button class="metal-button" data-exchange="${c.id}" ${state.points[c.faction]<3||state.phase!=="prepare"?"disabled":""}>兑换</button></div>`).join("")}</div></section></div>`,"forge");
    $("modal-content").querySelectorAll("[data-smelt]").forEach(b=>b.onclick=()=>showSmelt(b.dataset.smelt));
    $("modal-content").querySelectorAll("[data-exchange]").forEach(b=>b.onclick=()=>{if(execute({type:"exchange",id:b.dataset.exchange},"兑换成功 · 已计入同名份数"))showForge();});
  }
  $("forge-nav").onclick=showForge;
  function showSmelt(id){
    const c=M.get(state,id);if(!c)return;
    openModal(`<div class="modal-heading"><span class="eyebrow">RELEASE THE ESSENCE</span><h2>熔炼契约</h2><p>${c.name} · ${M.factions[c.faction].name}</p></div><div class="smelt-preview"><div>当前 ${c.copies} 份<br>Lv.${c.level}</div><b>⟶</b><div>${c.copies>1?`剩余 ${c.copies-1} 份 · Lv.${Math.min(3,c.copies-1)}`:"此卡将从秘库移除"}<br>获得 1 点${M.factions[c.faction].name}印记</div></div><p class="offer-note">仅熔炼一份。此操作无法通过「撤销配装」恢复。</p><div class="modal-buttons"><button class="metal-button" id="smelt-cancel">保留契约</button><button class="primary-button" id="smelt-confirm">确认熔炼 1 份</button></div>`,"smelt");
    $("smelt-cancel").onclick=closeModal;$("smelt-confirm").onclick=()=>{if(execute({type:"smelt",id},"已获得 1 点阵营印记"))showForge();};
  }
  $("confirm").onclick=()=>{
    if(!execute({type:"confirm"}))return;
    openModal(`<div class="confirmation"><div class="crest-icon"><svg><use href="#crest"/></svg></div><span class="eyebrow">THE PACT IS SEALED</span><h2>契约已缔结</h2><p>已锁定 ${Object.keys(state.slots).length} 张遗物 · COST ${M.used(state)} / ${M.budget(state)}<br>所有装载等级与槽位已冻结。</p><p class="subtle-note">交互原型到此完成构筑流程，尚未接入 Dota 战斗。</p><button id="return-prepare" class="primary-button">返回准备</button></div>`,"confirm");
    $("return-prepare").onclick=()=>{execute({type:"return"});closeModal();};
  };
  $("modal").addEventListener("close",()=>{if(state.phase==="locked"){execute({type:"return"});notify("已返回准备阶段");}});
  document.addEventListener("keydown",event=>{
    if(event.key==="Escape"&&!$("modal").open){selected=null;render();}
    if(event.key==="/"&&!$("modal").open&&!/INPUT|TEXTAREA|SELECT/.test(event.target.tagName)){event.preventDefault();$("search").focus();}
  });
  render();
})();
