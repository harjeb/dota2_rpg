(() => {
  'use strict';
  const cards = window.CARD_DESIGN_DATA;
  const $ = id => document.getElementById(id);
  const esc = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const factions = {
    E: ['元素', '#7cb9de', 'b4abc352-adac-4c04-b317-a50fda9b5ef7.png'],
    C: ['文明', '#e28d70', 'be9a6cb4-b644-4567-8cbc-dc19aac2eb63.png'],
    D: ['神域', '#dfcc98', 'cbc16103-fc85-4701-881d-4925517c5031.png'],
    A: ['深渊', '#b998d7', 'cc414802-49e5-4e01-a92f-5359e3ace084.png'],
    W: ['荒野', '#94bd8e', 'ea13d122-aee2-4716-856b-2ff57cbe5027.png']
  };
  const kinds = {g:['增益卡','↑'],c:['消耗卡','◷'],f:['场地卡','◎']};
  const axes = {'①':'生命','②':'护盾','③':'魔法','④':'充能层数','⑥':'控制','⑦':'节奏','⑧':'死亡印记','⑨':'重生','⑩':'施法'};
  const owned = ['C-g1','D-g1','A-g1','W-g1','C-c1','C-c3','D-c1','A-c4','W-c2','E-f1','E-f2','E-f3','C-g5','D-g3','A-g4','W-g4'];
  const heroes = ['龙骑士','莉娜','全能骑士','幻影刺客','兽王','宙斯','巫医','斧王'];
  const slots = ['C-g1','D-g1','A-g1','W-g1',null,null,null,null];
  const loads = Object.fromEntries(cards.map(c => [c.id,1]));
  let selected = 'C-c1', faction = 'all', kind = 'all', query = '', catalogue = false, timer;
  const get = id => cards.find(c => c.id === id);
  const cost = id => [1,5,10][loads[id]-1];
  const used = () => slots.reduce((sum,id) => sum + (id ? cost(id) : 0),0);
  const inventory = () => owned.filter(id => !slots.includes(id));
  function notify(text) { clearTimeout(timer); $('toast').textContent = text; timer = setTimeout(() => $('toast').textContent = '',5000); }
  function behavior(c) { return c.kind === 'f' ? '全战场 · 持续本场' : c.kind === 'c' ? `自动触发 · 共享 ${loads[c.id]} 次` : c.condition === '常驻' || !c.condition ? '被动能力 · 持续本场' : '条件联动 · 持续本场'; }
  function renderFilters() {
    $('factions').innerHTML = `<button data-faction="all" aria-pressed="${faction==='all'}">全部阵营</button>` + Object.entries(factions).map(([id,f]) => `<button data-faction="${id}" aria-pressed="${faction===id}" style="--accent:${f[1]}"><i></i>${f[0]}</button>`).join('');
    $('types').innerHTML = `<button data-kind="all" aria-pressed="${kind==='all'}">全部</button>` + Object.entries(kinds).map(([id,k]) => `<button data-kind="${id}" aria-pressed="${kind===id}">${k[1]} ${k[0]}</button>`).join('');
    $('library').setAttribute('aria-pressed',String(!catalogue)); $('catalogue').setAttribute('aria-pressed',String(catalogue));
  }
  function renderGrid() {
    const visible = cards.filter(c => (catalogue || inventory().includes(c.id)) && (faction==='all'||c.faction===faction) && (kind==='all'||c.kind===kind) && `${c.name} ${c.id} ${c.effect} ${c.condition} ${axes[c.axis]||''}`.toLowerCase().includes(query.toLowerCase()));
    $('library-title').textContent = catalogue ? '完整图鉴' : '本局卡库';
    $('inventory-count').textContent = `${inventory().length} / 24`;
    $('result-count').textContent = `显示 ${visible.length} 张`;
    $('library-note').textContent = catalogue ? '图鉴不代表拥有；选中查看原始三档效果。单卡 COST 尚待定档。' : '示例资产均拥有 Lv3；小卡效果按 Lv1 / Lv2 / Lv3 顺序展示。已装备卡不占容量。';
    $('cards').innerHTML = visible.map(c => `<button class="card" data-card="${c.id}" aria-pressed="${selected===c.id}" aria-label="${esc(c.name)}，${kinds[c.kind][0]}，${catalogue?'图鉴':`装载Lv${loads[c.id]}`}" style="--accent:${factions[c.faction][1]}"><span class="card-top"><span>${factions[c.faction][0]} · ${kinds[c.kind][0]}</span><span class="card-cost">${catalogue?'—':cost(c.id)} <small>C</small></span></span><span class="card-symbol" aria-hidden="true">${kinds[c.kind][1]}</span><strong class="card-name">${esc(c.name)}</strong><span class="card-effect">${esc(c.effect)}</span><span class="card-bottom"><span>${catalogue ? '图鉴 · 三档效果' : `装载 Lv${loads[c.id]} · 拥有 Lv3`}</span><span>${c.axis ? esc(axes[c.axis]||c.axis) : c.kind==='f'?'全战场':c.kind==='c'?'自动':'被动'}</span></span></button>`).join('');
    $('empty').hidden = visible.length !== 0;
  }
  function renderDetail() {
    const c = get(selected), level = loads[c.id], equipped = slots.indexOf(c.id), has = owned.includes(c.id);
    const condition = c.kind==='f' ? '开战生成；属性类按卡面在准备阶段结算。' : c.condition || '卡表未列额外触发条件。';
    const extra = c.kind==='f' ? '不锚定携带者；携卡英雄阵亡不解除。不同场地独立生效，持续到本场结束。' : c.kind==='c' ? (c.faction==='E' ? '默认共享次数按当前草案展示；元素原稿的后续触发、持续时间疑点仍待细化。' : '同卡冷却 12 秒。状态条件到期重新判断；事件条件等待新事件，冷却中不排队。') : '卡槽不代表唯一受益者；指定自身、装备者或特定目标的条款按原文执行。';
    $('detail').style.setProperty('--accent',factions[c.faction][1]);
    $('detail').innerHTML = `<div class="detail-kicker"><span>${factions[c.faction][0]} / 基础卡</span><span>${esc(c.id)}</span></div><h2>${esc(c.name)}</h2><div class="tags"><span>${kinds[c.kind][1]} ${kinds[c.kind][0]}</span><span>通用槽</span>${c.axis?`<span>联动线索 · ${esc(axes[c.axis]||c.axis)}</span>`:''}</div><p class="detail-label">卡面效果 · Lv1 / Lv2 / Lv3</p><div class="full-effect">${esc(c.effect)}</div><div class="condition"><strong>${behavior(c)}</strong>${esc(condition)}</div><p class="note">${extra}</p><p class="detail-label">${catalogue?'等级查看':'本场装载等级'} <span>· ${has?'示例拥有 Lv3':'图鉴未拥有'}</span></p><div class="level-picker">${[1,2,3].map(l => `<button data-level="${l}" aria-pressed="${l===level}" ${catalogue?'disabled':''}>Lv${l}<small>${[1,5,10][l-1]} C · 示例</small></button>`).join('')}</div><p class="note">${catalogue?'图鉴只读；三档效果保留原文。':'本稿统一借用普通档 1 / 5 / 10 演示预算；不代表该卡已定档。切换只更新装载 COST 与次数，原文三档并列保留。'}</p>${c.id==='E-f3'?'<div class="condition"><strong>共鸣领域的独立规则</strong>场地张数含自身，最多计 5 张；仅 Lv3 增幅其他场地。携卡英雄主属性合计不含本卡加成，不回算自身。</div>':''}<div class="detail-actions"><button id="equip-action" class="primary" ${catalogue||!has?'disabled':''}>${equipped>=0?'从阵容卸下':'选择通用槽装载'}</button></div><p class="note">${equipped>=0?`当前携卡英雄：${heroes[equipped]}`:has?'当前位于本局卡库':'当前未拥有'} · 唯一资产<br>消耗卡条件编辑、购买与熔炼流程见交互规范。</p>`;
    $('detail').querySelectorAll('[data-level]').forEach(button => button.onclick = () => { loads[c.id] = Number(button.dataset.level); render(); const fresh = $('detail').querySelector(`[data-level="${loads[c.id]}"]`); fresh.focus(); });
    $('equip-action').onclick = () => { if(catalogue || !has)return; if(equipped>=0) {slots[equipped]=null;render();notify(`${c.name}已退回卡库。`);} else {notify('点击底部任一通用槽。替换时原卡退回卡库。');$('roster').querySelector('[data-slot]').focus();} };
  }
  function renderRoster() {
    $('roster').innerHTML = heroes.map((hero,i) => { const c = get(slots[i]); return `<div class="hero"><div class="hero-name"><span>${hero}</span><small>Lv8</small></div><button class="slot exclusive" disabled title="本稿只接入基础卡表；专属卡保留入口">专属槽<small>该英雄专属卡</small></button><button class="slot ${c?'filled':''} ${!catalogue&&owned.includes(selected)?'eligible':''}" data-slot="${i}" style="--accent:${c?factions[c.faction][1]:'#77838a'}" aria-label="${hero}通用槽${c?'，'+c.name:'，空'}">${c?esc(c.name):'＋ 通用槽'}<small>${c?`Lv${loads[c.id]} · ${cost(c.id)} C`:'增益 / 消耗 / 场地'}</small></button></div>`; }).join('');
    $('budget-value').textContent = `${used()} / 64`; $('meter').style.width = `${Math.min(100,used()/64*100)}%`;
    $('budget-value').closest('.budget').classList.toggle('over',used()>64);
    $('budget-note').textContent = used()>64 ? `超出 ${used()-64} · 降低等级或卸卡` : '示例预算：8 位 Lv8 英雄';
    $('review').disabled = used()>64; $('review').textContent = used()>64?'COST 超出预算':'检查构筑';
  }
  function render() {renderFilters();renderGrid();renderDetail();renderRoster();}
  $('cards').onclick = e => {const b=e.target.closest('[data-card]');if(b){selected=b.dataset.card;render();$('cards').querySelector(`[data-card="${selected}"]`)?.focus();}};
  $('factions').onclick = e => {const b=e.target.closest('[data-faction]');if(b){faction=b.dataset.faction;renderFilters();renderGrid();$('factions').querySelector(`[data-faction="${faction}"]`).focus();}};
  $('types').onclick = e => {const b=e.target.closest('[data-kind]');if(b){kind=b.dataset.kind;renderFilters();renderGrid();$('types').querySelector(`[data-kind="${kind}"]`).focus();}};
  $('search').oninput = e => {query=e.target.value.trim();renderGrid();};
  $('library').onclick = () => {catalogue=false;render();}; $('catalogue').onclick = () => {catalogue=true;render();};
  $('clear').onclick = () => {faction=kind='all';query='';$('search').value='';render();$('search').focus();};
  $('roster').onclick = e => {
    const b=e.target.closest('[data-slot]');if(!b)return;const index=Number(b.dataset.slot);
    if(catalogue){if(slots[index]){selected=slots[index];render();}else notify('图鉴只读。切换到本局卡库后装载。');return;}
    if(!owned.includes(selected) || slots.includes(selected)) {if(slots[index]){selected=slots[index];render();}else notify('先从本局卡库选择一张未装备卡。');return;}
    const old=slots[index];slots[index]=selected;render();$('roster').querySelector(`[data-slot="${index}"]`).focus();notify(`${get(selected).name}已装入${heroes[index]}的通用槽${old?`；${get(old).name}退回卡库`:''}。`);
  };
  $('review').onclick = () => notify(`构筑检查通过：${slots.filter(Boolean).length} 张基础卡，COST ${used()} / 64。此设计稿不进入真实战斗。`);
  document.querySelectorAll('[data-view]').forEach(button => button.onclick = () => {
    document.querySelectorAll('[data-view]').forEach(b=>b.setAttribute('aria-pressed',String(b===button)));
    ['build','battle','backs'].forEach(id=>$(id).hidden=id!==button.dataset.view);
  });
  $('back-gallery').innerHTML = Object.entries(factions).map(([id,f],i) => `<figure class="back-item" style="--accent:${f[1]}"><img src="../../../pics/${f[2]}" alt="${f[0]}既有卡背原图"><figcaption>${f[0]}</figcaption><p>${kinds[['g','c','f','g','c'][i]][0]} · 卡外类型标识</p></figure>`).join('');
  document.querySelectorAll('.back-item img').forEach(img=>img.onerror=()=>{img.alt+='（本地原图缺失，请恢复 pics 素材）';});
  render();
})();
