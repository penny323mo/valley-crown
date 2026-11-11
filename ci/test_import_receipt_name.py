"""Mocked complete import orchestration. Never starts a child or samples a host."""
from pathlib import Path
from unittest.mock import patch
import contextlib,io,json,os,sys,tempfile,types
import guarded_manifest_ci as fixed
import diagnostic_policy as policy
SOURCE=Path(fixed.__file__).read_text()
BEFORE="""for name, path in diagnostic_policy.binding_inputs(package['diagnostic_binding']['side']).items():
            key = 'diagnostic:' + name; digest = package['diagnostic_binding']['bound_files_sha256'][name]
            artifacts[key] = checked(path, digest); expected[key] = digest"""
AFTER="""for binding_name, binding_path in diagnostic_policy.binding_inputs(package['diagnostic_binding']['side']).items():
            key = 'diagnostic:' + binding_name; digest = package['diagnostic_binding']['bound_files_sha256'][binding_name]
            artifacts[key] = checked(binding_path, digest); expected[key] = digest"""
assert SOURCE.count(AFTER)==1 and BEFORE not in SOURCE

def exercise(shadow=False,guard_fail=False,source_fail_at=None):
    module=types.ModuleType('mock_import_adapter');module.__file__=str(Path(fixed.__file__).resolve())
    exec(compile(SOURCE.replace(AFTER,BEFORE) if shadow else SOURCE,module.__file__,'exec'),module.__dict__)
    with tempfile.TemporaryDirectory(prefix='visibility-import-mock-') as temporary:
        root=Path(temporary);project=root/'project';project.mkdir();engine=root/'never-execute';engine.write_text('inert placeholder')
        archive=root/'source.zip';archive.write_text('inert');manifest=root/'manifest.json';manifest.write_text('{}');out=root/'evidence';xdg=root/'xdg'
        paths={n:root/(n+'.json') for n in ['policy','sources','snapshot','approval']}
        for p in paths.values():p.write_text('{}')
        package={'candidate':'vc-000000000000','runtime_manifest':{'sha256':'0'*64},'diagnostic_binding':{'side':'baseline','bound_files_sha256':{n:'0'*64 for n in paths}}}
        seen=[];calls=0
        def verify(*a,**k):
            nonlocal calls
            calls+=1
            if source_fail_at==calls:raise RuntimeError('SYNTHETIC source binding failure')
            return package,{}
        def run(path,argv,**kwargs):
            assert kwargs['limits'].timeout_s==300 and kwargs['limits'].max_rss_kib==2097152
            assert argv[1:]==['--headless','--editor','--path',str(project),'--import']
            assert set('diagnostic:'+n for n in paths)<=set(kwargs['artifacts'])
            seen.append(path.name)
            q={'passed':not guard_fail,'exit':0,'cleanup_complete':not guard_fail,'stop_reason':'SYNTHETIC_FAILURE' if guard_fail else None,'seconds':0,'sampled_peak_rss_kib':0,'mock_only':True}
            path.with_suffix('.json').write_text(json.dumps(q));path.with_suffix('.invocation.json').write_text('{"mock_only":true}');path.with_suffix('.log').write_text('SYNTHETIC NO PROCESS\n')
        monitor=types.SimpleNamespace(Limits=lambda **kw:types.SimpleNamespace(**kw),run=run)
        def receipt(p,inv):
            assert p.exists() and inv.exists();q=json.loads(p.read_text())
            if not q['passed']:raise RuntimeError('SYNTHETIC strict guard rejection')
            return q
        argv=['guarded_manifest_ci.py','import','--project',str(project),'--archive',str(archive),'--manifest',str(manifest),'--output',str(out),'--xdg',str(xdg),'--godot',str(engine),'--archive-sha256','0'*64,'--manifest-sha256','0'*64,'--hosted-execution-approved']
        with contextlib.ExitStack() as st:
            st.enter_context(patch.object(sys,'argv',argv));st.enter_context(patch.dict(os.environ,{'GITHUB_ACTIONS':'true','RUNNER_ENVIRONMENT':'github-hosted'}))
            st.enter_context(patch.object(module.shutil,'which',return_value=str(engine)));st.enter_context(patch.object(module,'checked',side_effect=lambda p,h:Path(p)))
            st.enter_context(patch.object(module,'verify_source',side_effect=verify));st.enter_context(patch.object(module,'inventory',return_value={}))
            st.enter_context(patch.object(module,'import_cache',return_value={'cache':'0'*64}));st.enter_context(patch.object(module,'load_monitor',return_value=monitor));st.enter_context(patch.object(module,'guard_receipt',side_effect=receipt))
            st.enter_context(patch.object(policy,'admitted',return_value=None));st.enter_context(patch.object(policy,'binding_inputs',return_value=paths))
            st.enter_context(patch('subprocess.Popen',side_effect=AssertionError('No processes allowed')))
            st.enter_context(contextlib.redirect_stdout(io.StringIO()));code=module.main()
        summary=json.loads((out/'phase-summary.json').read_text());marker=xdg/'import-complete.json'
        if shadow:
            assert code==1 and seen==['approval'] and not marker.exists();assert summary['error']['type']=='FileNotFoundError';assert (out/'approval.json').exists()
        elif guard_fail:
            assert code==1 and seen==['import'] and not marker.exists();assert not summary['passed'] and not summary['commands'];assert (out/'import.json').exists() and (out/'import.invocation.json').exists() and (out/'import.log').exists()
        elif source_fail_at:
            assert code==1 and not marker.exists() and not summary['passed'];assert 'SYNTHETIC source binding' in summary['error']['message']
            assert seen==([] if source_fail_at==2 else ['import'])
            if seen:assert (out/'import.json').exists()
        else:
            assert code==0 and seen==['import'] and summary['passed'];assert summary['commands'][0]['name']=='import';cert=json.loads(marker.read_text());assert cert['receipt']==str(out/'import.json') and cert['invocation']==str(out/'import.invocation.json')
            assert not (out/'approval.json').exists()
        return {'shadow':shadow,'guard_fail':guard_fail,'source_fail_at':source_fail_at,'passed':True,'processes_started':0}

results=[exercise(shadow=True),exercise(),exercise(guard_fail=True),exercise(source_fail_at=2),exercise(source_fail_at=3)]
print(json.dumps({'mock_only':True,'cases':results,'host_metrics_sampled':False,'engine_executed':False}))
