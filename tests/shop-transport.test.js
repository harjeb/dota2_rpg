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
    const text = JSON.stringify(s), pieces = text.match(/[\s\S]{1,256}/g);
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
receiver.chunk({version:1,shop_revision:3,rule_generation:2,index:1,count:1,data:"x".repeat(257)});
assert.equal(delivered.length,5,"oversized buffers rejected");
const reconnect = []; const reconnected = transport.create(s => reconnect.push(s));
reset.chunks.slice().reverse().forEach(reconnected.chunk);
assert.deepStrictEqual(reconnect,[reset.s],"new HUD accepts current full snapshot without old buffers");
// Completely dropped and partially dropped publications recover via receipt probes.
let probeTime = 0, receipts = [], recovered = [];
const recovering = transport.create(s => recovered.push(s), () => probeTime, s => receipts.push(s));
recovering.expire();
assert.deepStrictEqual(receipts[0], {rule_generation:-1, shop_revision:-1});
const lost = frames(9);
lost.chunks.slice(1).forEach(recovering.chunk);
probeTime = 5; recovering.expire();
assert.equal(receipts[1].shop_revision,-1,"partial receipt cannot acknowledge unseen inventory");
const replacement = frames(10);
replacement.chunks.forEach(recovering.chunk);
probeTime = 10; recovering.expire();
assert.equal(receipts[2].shop_revision,10,"fully committed replacement is acknowledged");
assert.equal(recovered.length,1);
for (let i=0;i<100;i++) recovering.expire();
assert.equal(receipts.length,3,"watch ticks cannot flood receipt requests");
probeTime = 15; recovering.expire();
assert.equal(receipts[3].shop_revision,10,"probe detects a completely lost newer server snapshot");
console.log("PASS shop transport atomic assembly, ordering, generations, expiry, reconnect, bounded buffers and loss recovery");
