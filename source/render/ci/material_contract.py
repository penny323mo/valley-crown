"""Narrow material proof contract. No executable final build exists in this draft."""
import hashlib
import json
import math
import re
from pathlib import Path

KINDS = ('villager', 'spearman', 'archer', 'scout')
LABEL = 'CONTROLLED MATERIAL STUDY NOT GAMEPLAY'
CONTRACTS = [dict(mode='material_studies', kind='native_controlled_material_study', frame_count=8),
             dict(mode='material_gameplay', kind='genuine_native_material_game_viewport', frame_count=2)]
HELPERS = ('run_native.py','scan_evidence.py','material_contract.py','xvfb_startup.py','guarded_manifest_ci.py','hardened_monitored_run.py','capture_material_base.gd','capture_material_studies.gd','capture_material_gameplay.gd','baseline_192.json')

# Closed source-authored diagnostic identifiers. Never evidence values or paths.
MATERIAL_ASSERTION_IDS = frozenset((
    'MC_LOCK_01',
    'MC_LOCK_02',
    'MC_LOCK_03',
    'MC_LOCK_04',
    'MC_LOCK_05',
    'MC_LOCK_06',
    'MC_LOCK_07',
    'MC_LOCK_08',
    'MC_LOCK_09',
    'MC_LOCK_10',
    'MC_LOCK_11',
    'MC_LOCK_12',
    'MC_LOCK_13',
    'MC_LOCK_14',
    'MC_LOCK_15',
    'MC_LOCK_16',
    'MC_LOCK_17',
    'MC_LOCK_18',
    'MC_LOCK_19',
    'MC_LOCK_20',
    'MC_MATERIAL_01',
    'MC_MATERIAL_02',
    'MC_MATERIAL_03',
    'MC_MATERIAL_04',
    'MC_MATERIAL_05',
    'MC_MATERIAL_06',
    'MC_MATERIAL_07',
    'MC_REPORT_01',
    'MC_REPORT_02',
    'MC_REPORT_03',
    'MC_REPORT_04',
    'MC_REPORT_05',
    'MC_REPORT_06',
    'MC_REPORT_07',
    'MC_REPORT_08',
    'MC_REPORT_09',
    'MC_REPORT_10',
    'MC_REPORT_11',
    'MC_REPORT_12',
    'MC_REPORT_13',
    'MC_REPORT_14',
    'MC_REPORT_15',
    'MC_REPORT_16',
    'MC_REPORT_17',
    'MC_REPORT_18',
    'MC_REPORT_19',
    'MC_REPORT_20',
    'MC_REPORT_21',
    'MC_REPORT_22',
    'MC_REPORT_23',
    'MC_REPORT_24',
    'MC_REPORT_25',
    'MC_REPORT_26',
    'MC_REPORT_27',
    'MC_REPORT_28',
    'MC_REPORT_29',
    'MC_REPORT_30',
    'MC_REPORT_31',
    'MC_REPORT_32',
    'MC_REPORT_33',
    'MC_REPORT_34',
    'MC_REPORT_35',
    'MC_REPORT_36',
    'MC_REPORT_37',
    'MC_REPORT_38',
    'MC_REPORT_39',
    'MC_REPORT_40',
    'MC_REPORT_41',
    'MC_REPORT_42',
    'MC_REPORT_43',
    'MC_REPORT_44',
    'MC_REPORT_45',
))

def need(ok, assertion_id):
    if not ok: raise ValueError('Material contract rejected: '+assertion_id)

def hash_ok(value):
    return type(value) is str and re.fullmatch('[0-9a-f]{64}', value) is not None

def validate_lock(lock):
    need(lock.get('reviewed_for_execution') is True, 'MC_LOCK_01')
    need(lock.get('diagnostic_only') is False and lock.get('fixed_fps') == 20, 'MC_LOCK_02')
    need(lock.get('capture_contract') in CONTRACTS, 'MC_LOCK_03')
    need(type(lock.get('build')) is str and re.fullmatch('vc-[0-9a-f]{12}',lock['build']), 'MC_LOCK_04')
    files=lock.get('project_files');need(type(files) is dict and len(files)==197, 'MC_LOCK_05')
    baseline=json.loads(Path(__file__).with_name('baseline_192.json').read_text())['files']
    added={'tests/'+name+'.gd.uid' for name in ('occlusion_geometry_contract','occlusion_observation_lifecycle','occlusion_stencil_contract','occlusion_stencil_matrix','occlusion_viewport_lifecycle')}
    need(set(files)==set(baseline)|added and lock.get('allowed_generated_uid_files')==[], 'MC_LOCK_06')
    for name,expected in baseline.items():
        if name=='main.tscn' or (name.startswith('scripts/') and name!='scripts/rules.gd') or name.endswith('.gdshader'):
            need(files[name]==expected, 'MC_LOCK_07')
    need(all(type(k) is str and not k.startswith('/') and '..' not in k.split('/') and hash_ok(v) for k,v in files.items()), 'MC_LOCK_08')
    for k in ('source_archive_sha256','godot_sha256','harness_sha256','supervisor_sha256','import_manifest_sha256','import_certificate_sha256'):
        need(hash_ok(lock.get(k)), 'MC_LOCK_09')
    binding=lock.get('material_binding');need(type(binding) is dict, 'MC_LOCK_10')
    need(set(binding)=={'native_scene_sha256','atlas_sha256','atlas_rgba8_sha256','native_adapter_sha256','generator_sha256','source_manifest_sha256'}, 'MC_LOCK_11')
    for key in ('native_adapter_sha256','generator_sha256','source_manifest_sha256'):need(hash_ok(binding[key]), 'MC_LOCK_12')
    need(binding['native_scene_sha256']=={f'assets/mature/models/{k}_action.scn':files[f'assets/mature/models/{k}_action.scn'] for k in KINDS}, 'MC_LOCK_13')
    for key in ('atlas_sha256','atlas_rgba8_sha256'):
        need(type(binding[key]) is dict and set(binding[key])=={'art/action_characters/textures/'+k+'_atlas.png' for k in KINDS} and all(hash_ok(v) for v in binding[key].values()), 'MC_LOCK_14')
    need(set(binding['atlas_sha256'])==set(binding['atlas_rgba8_sha256']), 'MC_LOCK_15')
    need(all(files.get(k)==v for k,v in binding['atlas_sha256'].items()), 'MC_LOCK_16')
    review=lock.get('independent_review');need(type(review) is dict and review.get('passed') is True and hash_ok(review.get('report_sha256')), 'MC_LOCK_17')
    for helper in HELPERS:
        need(lock['support_files'].get('ci/'+helper)==hashlib.sha256(Path(__file__).with_name(helper).read_bytes()).hexdigest(), 'MC_LOCK_18')
    need(lock['supervisor_sha256']==lock['support_files']['ci/run_native.py'], 'MC_LOCK_19')
    selected='capture_material_studies.gd' if lock['capture_contract']['mode']=='material_studies' else 'capture_material_gameplay.gd'
    need(lock['harness_sha256']==lock['support_files']['ci/'+selected], 'MC_LOCK_20')

def finite(v):return type(v) in (int,float) and math.isfinite(v)

def validate_materials(rows, kind, lock):
    need(type(rows) is list and len(rows)>0, 'MC_MATERIAL_01')
    target=lock['material_binding']['atlas_rgba8_sha256']['art/action_characters/textures/'+kind+'_atlas.png']
    need(any(row.get('texture_rgba8_sha256')==target for row in rows), 'MC_MATERIAL_02')
    for row in rows:
        need(type(row) is dict and type(row.get('mesh')) is str and type(row.get('surface')) is int, 'MC_MATERIAL_03')
        need(type(row.get('name')) is str and type(row.get('albedo')) is str and re.fullmatch('[0-9a-f]{8}',row['albedo']), 'MC_MATERIAL_04')
        need(finite(row.get('roughness')) and 0<=row['roughness']<=1 and finite(row.get('metallic')) and 0<=row['metallic']<=1, 'MC_MATERIAL_05')
        need(type(row.get('vertex_color')) is bool and type(row.get('texture_path')) is str, 'MC_MATERIAL_06')
        need(row.get('texture_rgba8_sha256')=='' or hash_ok(row.get('texture_rgba8_sha256')), 'MC_MATERIAL_07')


def validate_report(report, lock, pose_identity):
    mode=lock['capture_contract']['mode'];frames=report.get('frames');need(type(frames) is list and len(frames)==lock['capture_contract']['frame_count'] and all(type(f) is dict for f in frames), 'MC_REPORT_01')
    need(report.get('mode')==mode and report.get('failed')==0, 'MC_REPORT_02')
    need(report.get('fixed_fps')==20, 'MC_REPORT_03')
    source=report.get('source_sha256');need(type(source) is dict, 'MC_REPORT_04')
    need(all(source.get(k)==v for k,v in lock['project_files'].items()), 'MC_REPORT_05')
    need(set(source)-set(lock['project_files'])==set(lock['allowed_generated_uid_files']), 'MC_REPORT_06')
    prior_frame=-1
    for f in frames:
        need(f.get('fixed_fps')==20 and f.get('main_scene_sha256')==lock['project_files']['main.tscn'], 'MC_REPORT_07')
        need(f.get('action_controller_sha256')==lock['project_files']['scripts/action_character.gd'], 'MC_REPORT_08')
        need(f.get('material_binding')=={k:lock['material_binding'][k] for k in ('native_scene_sha256','atlas_sha256','atlas_rgba8_sha256')}, 'MC_REPORT_09')
        need(type(f.get('process_frame')) is int and f['process_frame']>prior_frame, 'MC_REPORT_10');prior_frame=f['process_frame']
        need(f.get('rendering_method')=='gl_compatibility' and f.get('rendering_driver')=='opengl3', 'MC_REPORT_11')
        need(finite(f.get('unix_time')) and f['unix_time']>0 and type(f.get('utc')) is str, 'MC_REPORT_12')
        need(f.get('lighting')==report.get('lighting') and type(f.get('camera')) is dict, 'MC_REPORT_13')
        light=f['lighting'];need(light.get('source')=='main.tscn runtime unmodified', 'MC_REPORT_14')
        need(finite(light.get('ambient_energy')) and abs(light['ambient_energy']-0.36)<1e-6 and finite(light.get('sun_energy')) and abs(light['sun_energy']-0.95)<1e-6 and light.get('sun_shadow') is True, 'MC_REPORT_15')
        need(light.get('ambient_color')=='b6bec5ff' and light.get('sun_color')=='ffedceff' and light.get('background_color')=='727967ff', 'MC_REPORT_16')
        need(light.get('tonemap')==0 and light.get('shadow_distance')==80, 'MC_REPORT_17')
        need(len(light.get('sun_rotation_degrees',[]))==3 and all(abs(a-b)<.0001 for a,b in zip(light['sun_rotation_degrees'],[-48,-32,0])), 'MC_REPORT_18')
        need(f['camera']['basis']==report['opening_camera']['basis'], 'MC_REPORT_19')
    if mode=='material_studies':
        need([(f.get('kind'),f.get('view')) for f in frames]==[(k,v) for k in KINDS for v in ('front','rear')], 'MC_REPORT_20')
        for f in frames:
            need(f.get('study_label')==LABEL and f.get('framebuffer')==[844,390], 'MC_REPORT_21')
            need(f.get('unit_state')=='controlled_paused_idle' and f.get('clip')=='idle' and f.get('overlay_disabled') is True, 'MC_REPORT_22')
            need(f['camera'].get('size')==3.2 and f.get('camera_scope')=='detail framing, not gameplay', 'MC_REPORT_23')
            poses=f.get('animation_poses');need(type(poses) is list and len(poses)==1, 'MC_REPORT_24')
            need(poses[0].get('kind')==f['kind'] and poses[0].get('clip')=='idle' and poses[0].get('occlusion',{}).get('authorized') is False, 'MC_REPORT_25')
            pose_identity(poses[0],lock)
            validate_materials(f.get('materials'),f['kind'],lock)
    else:
        need([f['label'] for f in frames]==['opening','worker-walking'], 'MC_REPORT_26')
        need(all(f.get('test_mode') is False and f.get('economy_audit_ok') is True for f in frames), 'MC_REPORT_27')
        need(all(f['camera']==report['opening_camera'] for f in frames), 'MC_REPORT_28')
        inputs=report.get('inputs');need(type(inputs) is list and len(inputs)==6, 'MC_REPORT_29')
        need([(i.get('action'),i.get('pressed')) for i in inputs]==[('worker-select',True),('worker-select',False),('command-enter',True),('command-enter',False),('worker-move',True),('worker-move',False)], 'MC_REPORT_30')
        need(all(i.get('route')=='root.push_input InputEventScreenTouch' and len(i.get('position',[]))==2 and all(finite(v) for v in i['position']) for i in inputs), 'MC_REPORT_31')
        f=frames[1];worker=report.get('worker_id');need(type(worker) is int and worker>=0, 'MC_REPORT_32')
        need(inputs[4].get('touch_command_before') is True and inputs[4].get('selected_before')==[worker], 'MC_REPORT_33')
        need(f.get('selected')==[worker] and f.get('worker_visible') is True, 'MC_REPORT_34')
        probe=f.get('visibility_probe');need(type(probe) is dict and probe.get('clear') is True and probe.get('sample_count')==3 and probe.get('blocker_count')==0, 'MC_REPORT_35')
        samples=probe.get('samples');need(type(samples) is list and len(samples)==3, 'MC_REPORT_36')
        for sample in samples:
            need(type(sample) is dict and sample.get('height') in (.7,1.1,1.5), 'MC_REPORT_37')
            for name,length in (('world',3),('screen',2),('ray_origin',3)):
                need(type(sample.get(name)) is list and len(sample[name])==length and all(finite(v) for v in sample[name]), 'MC_REPORT_38')
        bounds=probe.get('projected_body_bounds');need(type(bounds) is list and len(bounds)==4 and all(finite(v) for v in bounds) and bounds[2]>0 and bounds[3]>0, 'MC_REPORT_39')
        overlay=probe.get('overlay',{});need(overlay.get('authorized') is True and overlay.get('supported') is True, 'MC_REPORT_40')
        nodes=probe.get('overlay_nodes');need(type(nodes) is list and len(nodes)==overlay.get('overlay_meshes') and len(nodes)>0, 'MC_REPORT_41')
        need(all(n.get('visible') is True and n.get('visible_in_tree') is True and n.get('shader_sha256')==lock['project_files']['assets/mature/shaders/observed_occlusion.gdshader'] for n in nodes), 'MC_REPORT_42')
        validate_materials(probe.get('materials'),'villager',lock)
        own=[r for r in f['own_units'] if r['id']==worker];need(len(own)==1 and own[0]['state']=='move', 'MC_REPORT_43')
        pose=f['animation_poses'][0]['snapshot']['live'][str(worker)]
        need(pose.get('kind')=='villager' and pose.get('clip')=='walk', 'MC_REPORT_44');pose_identity(pose,lock)
        original=[r for r in frames[0]['own_units'] if r['id']==worker];need(len(original)==1 and original[0]['pos']!=own[0]['pos'], 'MC_REPORT_45')
    return [{'kind':'human_material_pixel_review_required','reason':'AABB visibility and source binding do not prove skin/clothing color or absence of silhouette whitening in pixels'}]
