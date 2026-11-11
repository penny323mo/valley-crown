"""Pure evidence checks. No launch, host probe, source mutation or promotion API."""
import math
import re
from gpu_identity import identity as gpu_identity

LIMITS = dict(systemd_runtime_seconds=100, node_runtime_seconds=90,
              supervisor_cleanup_seconds=105, stop_timeout_seconds=5,
              memory_bytes=3*1024**3, swap_bytes=0, tasks=256, cpu_percent=200)

def need(ok, message):
    if not ok:
        raise ValueError(message)

def digest(value):
    return isinstance(value, str) and re.fullmatch('[0-9a-f]{64}', value) is not None

def ready(manifest):
    for key in ('reviewed', 'bound', 'execution_approved'):
        need(manifest.get(key) is True, 'Unadmitted: '+key)
    need(manifest.get('diagnostic_only') is True and manifest.get('release_artifact_identity_claim') is False, 'Diagnostic identity required')
    need(manifest.get('scenario') == 'visibility-paused-startup' and manifest.get('profile') == 'portrait' and manifest.get('viewport') == [390,844], 'Fixed scenario differs')
    need(re.fullmatch('[0-9a-f]{40}',manifest.get('source_commit','')) is not None, 'Final source commit unbound')
    need(re.fullmatch('[0-9a-f]{40}',manifest.get('game_tree','')) is not None, 'Final source tree unbound')
    for key in ('game_source_sha256','overlay_sha256','diagnostic_source_inventory_sha256','export_artifact_sha256','qa_inventory_sha256',
                'source_archive_sha256','import_manifest_sha256','export_manifest_sha256','source_chain_verification_sha256'):
        need(digest(manifest.get(key)), 'Unbound '+key)
    files=manifest.get('files_sha256',{})
    need(all(digest(files.get(k)) for k in ('index.html','index.js','index.wasm','index.pck')), 'Diagnostic Web bytes unbound')

def number(value):
    return type(value) in (int,float) and math.isfinite(value)

def checked_arm(evidence, host, expected):
    ready(expected)
    need(evidence.get('manifest')==expected, 'Unexpected diagnostic manifest')
    need(evidence.get('schema')=='vc-paused-browser-v1' and evidence.get('phase')=='completed' and evidence.get('basicSmokePassed') is True, 'Browser did not finish successfully')
    need(evidence.get('automatic_promotion') is False and evidence.get('releaseQAPassed') is False, 'No release-acceptance claim allowed')
    need(evidence.get('error_count')==0 and not evidence.get('errors'), 'Browser/network failure')
    need(number(evidence.get('elapsed_ms')) and evidence['elapsed_ms']<70000, 'Original scenario deadline exceeded')
    need(host.get('passed') is True and host.get('cleanup_verified') is True and host.get('post_run_inputs_unchanged') is True, 'Guard, cleanup or input verification missing')
    need(host.get('limits')==LIMITS, 'Original guard limits differ')
    need(host.get('files_sha256')==expected['files_sha256'], 'Guard export bytes differ')
    need(host.get('source_commit')==expected['source_commit'] and host.get('build')==expected['build'], 'Guard source identity differs')
    need(len(evidence.get('screenshots',[]))==1 and evidence['screenshots'][0].get('genuine_browser_capture') is True, 'One genuine PNG required')
    need(digest(evidence['screenshots'][0].get('sha256')) and evidence['screenshots'][0].get('viewport')==[390,844], 'PNG identity/dimensions missing')
    need(evidence.get('observation',{}).get('bridge_immutable') is True, 'Read-only bridge contract absent')
    need(evidence.get('reads') and all(number(x.get('duration_ms')) and 0<=x['duration_ms']<=5000 for x in evidence['reads']), 'Original read cap exceeded')
    r=evidence.get('report',{})
    need(r.get('schema')=='vc-paused-visibility-v1' and r.get('phase')=='completed', 'Measurement incomplete')
    need(r.get('diagnostic_only') is True and r.get('normal_gameplay_fps') is False, 'Incorrect throughput scope')
    need(r.get('build')==expected.get('build'), 'Engine build differs')
    observed_hashes={}
    for key in ('game_source_sha256','overlay_sha256'):
        value=r.get(key)
        need(isinstance(value,str), 'Runtime FileAccess result missing: '+key)
        status='unavailable' if value=='' else 'observed'
        need(r.get('runtime_source_hash_status',{}).get(key)==status, 'Runtime hash status mislabelled: '+key)
        if value!='':need(value==expected.get(key), 'Nonempty observed source hash differs: '+key)
        observed_hashes[key]=dict(status=status,value=value)
    a,b=r.get('begin',{}),r.get('end',{})
    need(a.get('state')==b.get('state')==r.get('current_state'), 'Scene changed')
    state=b['state']
    need(state.get('viewport')==[390,844] and state.get('paused') is True and state.get('ai_enabled') is True and state.get('test_mode') is False and state.get('focused') is True and state.get('suspended') is False, 'Invalid paused scene flags')
    need(state.get('engine_time_scale')==1 and state.get('public',{}).get('tick')==0 and state.get('public',{}).get('time')==0, 'Simulation progressed or clock changed')
    need(state.get('engine_max_fps')==0 and state.get('content_scale_factor')==1, 'Unexpected cap or render scale')
    need(digest(state.get('records_sha256')) and state.get('record_count',0)>0, 'Public scene fingerprint absent')
    for sample in (a,b):
        need(all(type(sample.get(k)) is int and sample[k]>=0 for k in ('wall_usec','process_frames','product_process_frames','drawn_frames')), 'Invalid actual counters')
    need(r.get('warmup_target_usec')==3000000 and r.get('measurement_target_usec')==6000000, 'Fixed windows changed')
    need(a['wall_usec']-r.get('first_draw_usec',a['wall_usec'])>=3000000, 'Warmup too short')
    wall=(b['wall_usec']-a['wall_usec'])/1e6
    need(6<=wall<=7, 'Measurement missed fixed window boundary; retain as inconclusive')
    frames={k:b[k]-a[k] for k in ('process_frames','product_process_frames','drawn_frames')}
    need(all(v>0 for v in frames.values()) and frames['process_frames']==frames['product_process_frames'], 'Missing ordinary product process frames')
    need(type(r.get('draw_samples')) is int and r['draw_samples']==frames['drawn_frames'], 'Draw samples/frame count mismatch')
    need(all(type(r.get(k)) is int and r[k]>0 for k in ('draw_call_sum','draw_call_min','draw_call_max')), 'Draw counters unsupported/empty')
    need(r['draw_call_min']<=r['draw_call_sum']/r['draw_samples']<=r['draw_call_max'], 'Draw monitor aggregate inconsistent')
    need(number(r.get('process_monitor_seconds_sum')) and r['process_monitor_seconds_sum']>=0, 'Process monitor absent')
    env=evidence.get('environment',{})
    need(env.get('executed_argv',{}).get('status')=='observed' and env.get('gpu',{}).get('status')=='observed', 'Actual argv/GPU unknown')
    selected_gpu=gpu_identity(env['gpu']['value'])
    need(selected_gpu['status']=='observed', 'Renderer/device/driver identity unknown: '+selected_gpu.get('reason',''))
    argv=env['executed_argv'].get('value',{}).get('arguments')
    need(isinstance(argv,list) and all(isinstance(x,str) for x in argv) and argv, 'Executed argv missing')
    need(not any(x in ('--no-sandbox','--disable-setuid-sandbox') for x in argv), 'Sandbox bypass observed')
    normalized=[('--user-data-dir=<fresh-profile>' if x.startswith('--user-data-dir=') else x) for x in argv]
    need(digest(host.get('chrome_sha256')) and digest(host.get('node_sha256')), 'Runtime executable identity absent')
    return dict(state=state,renderer=r.get('renderer'),argv=normalized,gpu=env['gpu']['value'],gpu_identity=selected_gpu['value'],
                source_identity_basis='Reviewed independently verified diagnostic input/import/export/PCK chain; not runtime measurement',
                source_chain_verification_sha256=expected['source_chain_verification_sha256'],runtime_source_hashes=observed_hashes,
                browser_version=env.get('browser_version'),chrome_sha256=host['chrome_sha256'],node_sha256=host['node_sha256'],
                wall_seconds=wall,**frames,draw_samples=r['draw_samples'],draw_call_sum=r['draw_call_sum'],
                draw_calls_mean=r['draw_call_sum']/r['draw_samples'],draw_calls_min=r['draw_call_min'],draw_calls_max=r['draw_call_max'],
                process_monitor_seconds_sum=r['process_monitor_seconds_sum'],paused_drawn_frames_per_wall_second=frames['drawn_frames']/wall)

def compare(baseline,candidate,baseline_host,candidate_host,baseline_manifest,candidate_manifest):
    result=dict(status='inconclusive',automatic_promotion=False,normal_gameplay_fps=False,
                evidence_scope='One sequential pair, uncontrolled hosted CPU/GPU scheduling; no statistical speedup claim')
    try:
        need(baseline_manifest.get('side')=='baseline' and candidate_manifest.get('side')=='candidate', 'Pair labels missing')
        need(baseline_manifest.get('overlay_sha256')==candidate_manifest.get('overlay_sha256'), 'Observer source differs')
        need(baseline_manifest.get('game_source_sha256')!=candidate_manifest.get('game_source_sha256'), 'Product implementations are identical')
        a=checked_arm(baseline,baseline_host,baseline_manifest)
        b=checked_arm(candidate,candidate_host,candidate_manifest)
        for key in ('state','renderer','argv','gpu_identity','browser_version','chrome_sha256','node_sha256'):
            need(a[key]==b[key], 'Paired environment/scene differs: '+key)
        result.update(status='descriptive_pair_only',baseline=a,candidate=b,
                      observed_rate_ratio=b['paused_drawn_frames_per_wall_second']/a['paused_drawn_frames_per_wall_second'])
    except (ValueError,KeyError,TypeError,ZeroDivisionError) as error:
        result['reason']=str(error)
    return result
