"use strict";
const assert = require("assert");
const transport = require("../content/dota_addons/dota2_rpg/panorama/scripts/custom_game/shop_transport.js");
let clock = 0, delivered = [];
const receiver = transport.create(s => delivered.push(s), () => clock);
function frames(revision, generation = 1) {
    const s = {shop_revision: revision, rule_generation: generation, gold: revision,
        inventories_text: Array(180).fill("npc_dota_hero_axe:item_ultimate_scepter,item_butterfly,item_assault").join(";"),
        equipped_text: Array(180).fill("npc_dota_hero_axe:item_ultimate_scepter|123|0,item_butterfly|456|1").join(";"),
        unicode: "中立装备\\\"\n"};
    const text = JSON.stringify(s), pieces = text.match(/[\s\S]{1,1200}/g);
    return {s, chunks: pieces.map((data, i) => ({version:1, shop_revision:revision, rule_generation:generation,index:i+1,count:pieces.length,data}))};
}
let first = frames(1);
first.chunks.slice(1).reverse().forEach(c => { receiver.chunk(c); receiver.chunk(c); });
assert.equal(delivered.length, 0, "partial snapshot never publishes wallet/inventory");
receiver.chunk(first.chunks[0]);
assert.deepStrictEqual(delivered, [first.s]);
first.chunks.forEach(receiver.chunk);
assert.equal(delivered.length, 1, "completed duplicates ignored");
let old = frames(2), newer = frames(3);
receiver.chunk(old.chunks[0]); receiver.chunk(newer.chunks[0]);
old.chunks.forEach(receiver.chunk); newer.chunks.slice(1).forEach(receiver.chunk);
assert.deepStrictEqual(delivered[1], newer.s, "revisions cannot mix");
let partial = frames(4); receiver.chunk(partial.chunks[0]);
receiver.normal({shop_revision:5,rule_generation:1,gold:5});
partial.chunks.forEach(receiver.chunk);
assert.equal(delivered.length,3,"small snapshot supersedes pending large snapshot");
const reset = frames(1,2); reset.chunks.forEach(receiver.chunk);
receiver.normal({shop_revision:999,rule_generation:1,gold:999});
assert.equal(delivered.length,4,"old generation rejected");
let timeout = frames(2,2); receiver.chunk(timeout.chunks[0]); clock=16; receiver.expire();
timeout.chunks.slice(1).forEach(receiver.chunk);
assert.equal(delivered.length,4,"expired fragment not retained");
timeout.chunks.forEach(receiver.chunk); assert.equal(delivered.length,5);
receiver.chunk({version:1,shop_revision:3,rule_generation:2,index:1,count:513,data:"x"});
receiver.chunk({version:1,shop_revision:3,rule_generation:2,index:1,count:1,data:"x".repeat(1201)});
assert.equal(delivered.length,5,"oversized buffers rejected");
const reconnect = []; const reconnected = transport.create(s => reconnect.push(s));
reset.chunks.slice().reverse().forEach(reconnected.chunk);
assert.deepStrictEqual(reconnect,[reset.s],"new HUD accepts current full snapshot without old buffers");
console.log("PASS shop transport atomic assembly, ordering, generations, expiry, reconnect, bounded buffers");
