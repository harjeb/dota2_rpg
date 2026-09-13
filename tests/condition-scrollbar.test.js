const fs=require('fs'),assert=require('assert');
const css=fs.readFileSync('content/dota_addons/dota2_rpg/panorama/styles/custom_game/rpg_demo_hud.css','utf8');
assert(/\.RulesContainer\s*\{[^}]*overflow:\s*squish scroll/.test(css),'rule list still scrolls');
assert(/\.RuleSettingsBody\s*\{[^}]*overflow:\s*squish scroll/.test(css),'condition editor still scrolls');
assert(/\.RulesContainer VerticalScrollBar\s*\{[^}]*visibility:\s*collapse/.test(css),'rule list thin scrollbar hidden');
assert(/\.RuleSettingsBody VerticalScrollBar[^}]*visibility:\s*collapse/.test(css),'condition pane scrollbar hidden');
console.log('PASS condition scrollbars hidden while wheel scrolling retained');
