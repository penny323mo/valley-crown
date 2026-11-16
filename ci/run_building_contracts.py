#!/usr/bin/env python3
"""Prepared only. Six exact suites under unchanged original run_logic.supervise."""
import argparse
import json
import os
from pathlib import Path
import run_export as r
import run_logic as logic
import validate_building_contracts as v
p=r.p
LOGIC_SHA="2800e75273335ce8ffefccb1db6128b54f09850b50dc243cf73e7065ff107607"
OWNED_SHA="7fd227386d083f35bf55390a26a96c70472ba4a0def0f781f9a28aeeaa59cb2e"

def harness_paths(project):
    return {s:Path(__file__).with_name("building-fixtures")/(s+".gd") if s in v.EXTERNAL
            else project/"tests"/(s+".gd") for s in v.SUITES}

def argv(godot,project,suite,harness,stage):
    p.require(suite in v.SUITES,"Unsupported suite")
    script=str(harness) if suite in v.EXTERNAL else "res://tests/"+suite+".gd"
    command=[str(godot),"--headless","--path",str(project),"--audio-driver","Dummy",
             "--resolution","390x844","--fixed-fps","30","--script",script]
    if suite=="construction_visual": command += ["--",str(stage/v.REPORT)]
    return command

def run(args):
    lockpath=r.path_checked(args.lock);lock=v.parse_json(p.regular(lockpath).read_text())
    v.validate_identity(lock);r.validate_lock(lock)
    p.require(os.environ.get("GITHUB_ACTIONS")=="true" and os.environ.get("RUNNER_ENVIRONMENT")=="github-hosted","Hosted VM required")
    p.require('VERSION_ID="24.04"' in Path('/etc/os-release').read_text(),'Ubuntu 24.04 required')
    project,output,private=map(r.path_checked,(args.project,args.output,args.private))
    paths=[project,output,private]
    p.require(project.is_dir() and not output.exists() and not private.exists(),"Fresh output/private required")
    p.require(len(set(paths))==3 and all(not a.is_relative_to(b) for a in paths for b in paths if a!=b),"Overlapping paths")
    godot=r.checked(args.godot,r.ENGINE_SHA)
    p.require(lock.get("building_supervisor_sha256")==LOGIC_SHA and lock.get("owned_process_sha256")==OWNED_SHA,"Unreviewed supervision bytes")
    required={"runner_sha256":r.__file__,"owned_process_sha256":p.__file__,
              "building_runner_sha256":__file__,"building_validator_sha256":v.__file__,
              "building_supervisor_sha256":logic.__file__}
    bound=[lockpath,godot]+[r.checked(path,lock[key]) for key,path in required.items()]
    harnesses=harness_paths(project)
    hashes=lock.get("building_harness_sha256")
    p.require(type(hashes) is dict and set(hashes)==set(v.SUITES),"Exact six harness bindings required")
    for suite,path in harnesses.items():
        if suite in v.EXTERNAL: p.require(not path.is_relative_to(project),"External harness inside product")
        else: p.require(hashes[suite]==lock["project_files"]["tests/"+suite+".gd"],"Source harness identity mismatch")
        bound.append(r.checked(path,hashes[suite]))
    source,uids=p.source_inventory(project,lock);cache=p.cache_inputs(project)
    p.require(cache,"Guarded real import required")
    marker=r.path_checked(args.import_marker);bound.append(marker)
    bound+=r.validate_import(project,lock,marker,cache,uids)
    bindings={str(x):p.digest(x) for x in bound}
    output.mkdir(parents=True);private.mkdir(parents=True,mode=0o700)
    receipt={"passed":False,"build":lock["build"],"source_commit":lock["source_commit"],"game_tree":lock["game_tree"],
             "scope":"Controlled headless building contracts only; no rendered visual, ordinary-match, browser or device acceptance",
             "input_sha256":bindings,"generated_uid_sha256":uids,"suites":[]}
    def unchanged():
        p.require(p.source_inventory(project,lock,uids)[0]==source and p.cache_inputs(project)==cache,"Source/UID/import cache drift")
        p.require(all(p.digest(p.regular(r.path_checked(path)))==sha for path,sha in bindings.items()),"Bound input drift")
    try:
        for suite in v.SUITES:
            unchanged()
            work=private/suite;work.mkdir(mode=0o700)
            env={"PATH":"/usr/bin:/bin","LANG":"C.UTF-8","TZ":"UTC","GODOT_SILENCE_ROOT_WARNING":"1","OMP_NUM_THREADS":"1"}
            for key,name in [("HOME","home"),("TMPDIR","tmp"),("XDG_DATA_HOME","data"),("XDG_CONFIG_HOME","config"),("XDG_CACHE_HOME","cache")]:
                path=work/name;path.mkdir(mode=0o700);env[key]=str(path)
            stage=output/suite;stage.mkdir()
            result=logic.supervise(argv(godot,project,suite,harnesses[suite],stage),env,stage,p.metrics())
            row={"suite":suite,"monitor":result};receipt["suites"].append(row)
            v.validate_monitor(result)
            unchanged()
            expected={"receipt.json","godot.log"}|({v.REPORT} if suite=="construction_visual" else set())
            p.require(set(p.tree(stage))==expected,"Unexpected suite files")
            p.require(v.parse_json((stage/"receipt.json").read_text())==result,"Monitor receipt mismatch")
            row["report"]=v.read_report(stage,suite)
            row["assertions_executed"]=v.COUNTS[suite]
            row["receipt_sha256"]=p.digest(stage/"receipt.json");row["log_sha256"]=p.digest(stage/"godot.log")
            if suite=="construction_visual":row["report_sha256"]=p.digest(stage/v.REPORT)
            p.require(row["log_sha256"]==result["log_sha256"],"Log drift")
            unchanged()
        receipt["assertions_executed"]=sum(row["assertions_executed"] for row in receipt["suites"])
        receipt["passed"]=True
    except BaseException as exc:
        receipt["error"]={"type":type(exc).__name__,"message":p.safe_diagnostic_text(exc)}
    finally:
        try:
            unchanged();receipt["post_run_binding_matches"]=True
        except BaseException as exc:
            receipt["passed"]=False;receipt["post_run_binding_matches"]=False
            receipt["binding_error"]={"type":type(exc).__name__,"message":p.safe_diagnostic_text(exc)}
        (output/"building-contracts-receipt.json").write_text(json.dumps(receipt,indent=2)+"\n")
        print(json.dumps({"passed":receipt["passed"],"scope":receipt["scope"],"error":receipt.get("error")}))
    return 0 if receipt["passed"] else 1

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    for key in ("lock","project","output","private","godot","import-marker"):parser.add_argument("--"+key,type=Path,required=True)
    raise SystemExit(run(parser.parse_args()))
