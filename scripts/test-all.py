"""Run portable offline regression gates. Node and Lua are mandatory (no skips).
Usage: python scripts/test-all.py
Set LUA_BIN for a nonstandard Lua installation. Does not launch Dota or Hammer.
"""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests'))
from lua_test_runtime import interpreter, lua_literal, run_lua

def main():
    lua=interpreter()
    results=[]
    commands=[('generated_profiles',[sys.executable,'scripts/build-ability-capabilities.py','--check'])]
    commands += [(str(p.relative_to(ROOT)),[lua,str(p.relative_to(ROOT))]) for p in sorted((ROOT/'tests').glob('*.test.lua'))]
    commands += [(str(p.relative_to(ROOT)),['node',str(p.relative_to(ROOT))]) for p in sorted((ROOT/'tests').glob('*.test.js'))]
    commands += [(str(p.relative_to(ROOT)),[sys.executable,str(p.relative_to(ROOT))]) for p in sorted((ROOT/'tests').glob('*.test.py'))]
    for name,cmd in commands:
        started=time.monotonic()
        try:
            run=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=90)
            code,out,err=run.returncode,run.stdout,run.stderr
        except (subprocess.TimeoutExpired,OSError) as exc:
            code,out,err=1,'',str(exc)
        results.append({'test':name,'returncode':code,'seconds':round(time.monotonic()-started,3),'stdout':out,'stderr':err})
        print(('PASS ' if not code else 'FAIL ')+name,flush=True)
        if code: print((out+err)[-2500:],flush=True)
    # Parse every source, including optional adapters not executed by test doubles.
    files=sorted((ROOT/'game/dota_addons/dota2_rpg/scripts/vscripts').rglob('*.lua'))
    source='for _,path in ipairs('+lua_literal([str(p) for p in files])+') do local chunk,err=loadfile(path); assert(chunk,err) end\n'
    try:
        run_lua(source); results.append({'test':'all_lua_source_syntax','returncode':0,'files':len(files)})
    except Exception as exc: results.append({'test':'all_lua_source_syntax','returncode':1,'stderr':str(exc)})
    js=sorted((ROOT/'content/dota_addons/dota2_rpg/panorama/scripts/custom_game').glob('*.js'))
    failures=[]
    for p in js:
        run=subprocess.run(['node','--check',str(p)],cwd=ROOT,capture_output=True,text=True,timeout=30)
        if run.returncode: failures.append({'file':str(p.relative_to(ROOT)),'stderr':run.stderr})
    results.append({'test':'all_panorama_source_syntax','returncode':int(bool(failures)),'files':len(js),'failures':failures})
    failed=[r['test'] for r in results if r['returncode']]
    report={'scope':'offline-only; Lua native-API mocks and Node Panorama panel doubles; Dota/Workshop execution not tested',
        'test_groups':len(results),'passed':len(results)-len(failed),'failed':failed,'results':results}
    dest=ROOT/'tests/results/reliability-regression.json';dest.parent.mkdir(parents=True,exist_ok=True)
    dest.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in report.items() if k!='results'},ensure_ascii=False))
    return 1 if failed else 0
if __name__=='__main__': raise SystemExit(main())
