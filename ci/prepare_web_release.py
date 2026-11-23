#!/usr/bin/env python3
"""Exact product/controlled-diagnostic preparation; no engine in prepare phase."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BRANCH = 'refs/heads/main'
SOURCE = '40ed8f286d56459bd304568d6131909d00764736'
ENGINE = '4.6.3.stable.official.7d41c59c4'
ENGINE_SHA = 'f64d4ed19fc9df9440321653fcc80df8c6e365ba7b6de0a29e2cfa9fa71bfeb3'
TEMPLATE_SHA = '1446f79dc12f60ce5d244c39fb6628ec298337ca5c4f91a16491feea72aa1bc9'
SIDES = {
    'product': {'directory':'game', 'build':'vc-48407f5501e4', 'tree':'9db74af4c2f59ad0673d0bc7880b0d033150ba37', 'files':778, 'runtime':353, 'runner':'run_export.py'},
    'diagnostic': {'directory':'diagnostic-game', 'build':'vc-09c394aef6d8', 'tree':'5d478c5414ba732f41b109515e90d45495406a1b', 'files':258, 'runtime':155, 'runner':'run_export_diagnostic.py'},
}
OUTPUT_FILES = sorted(['index.html','index.js','index.wasm','index.pck','index.png','index.icon.png','index.apple-touch-icon.png','index.audio.worklet.js','index.audio.position.worklet.js'])


def need(value, message):
    if not value: raise ValueError(message)


def sha(path):
    with Path(path).open('rb') as stream: return hashlib.file_digest(stream,'sha256').hexdigest()


def dump(path, value):
    with path.open('x') as stream:
        json.dump(value,stream,indent=2,sort_keys=True);stream.write('\n')


def admitted():
    need(os.environ.get('GITHUB_ACTIONS')=='true' and os.environ.get('RUNNER_ENVIRONMENT')=='github-hosted','Fresh hosted runner required')
    need(os.environ.get('GITHUB_REPOSITORY')=='penny323mo/valley-crown' and os.environ.get('GITHUB_REF')==BRANCH and os.environ.get('GITHUB_RUN_ATTEMPT')=='1','Wrong repository/branch/attempt')
    need(os.environ.get('BUILDING_RUNTIME_EXECUTION_APPROVED')=='true','Second-stage execution not reviewed')
    need('VERSION_ID="24.04"' in Path('/etc/os-release').read_text(),'Ubuntu24.04 required')
    need(re.fullmatch('[a-f0-9]{40}',SOURCE),'Unbound product source commit')
    need(os.environ.get('BUILDING_RUNTIME_SOURCE_COMMIT')==SOURCE,'Workflow source pin differs')


def git(*args):
    return subprocess.check_output(['git','-C',str(ROOT),*args],text=True,timeout=8).strip()


def prepare(side, work):
    identity=SIDES[side];project=ROOT/identity['directory'];work=work.absolute()
    need(git('rev-parse','HEAD:'+identity['directory'])==identity['tree'],'Public source tree differs')
    need(git('rev-parse',SOURCE+':'+identity['directory'])==identity['tree'],'Pinned source commit tree differs')
    need(not work.exists() and not any(p.is_symlink() for p in [work,*work.parents]),'Fresh real work root required')
    need(not work.is_relative_to(ROOT) and not ROOT.is_relative_to(work),'Source/work overlap')
    public={}
    for line in git('ls-tree','-r','HEAD:'+identity['directory']).splitlines():
        meta,name=line.split('\t',1);mode,kind,digest=meta.split()
        need(mode=='100644' and kind=='blob','Nonregular public source');public[name]=digest
    files={};actual={}
    for path in sorted(project.rglob('*')):
        need(not path.is_symlink(),'Source symlink')
        if path.is_dir():continue
        need(path.is_file(),'Special source');name=path.relative_to(project).as_posix();data=path.read_bytes()
        actual[name]=hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
        files[name]={'file':name,'size':len(data),'sha256':hashlib.sha256(data).hexdigest()}
    need(actual==public and len(actual)==identity['files'],'Exact public source bytes/count differ')
    spec=importlib.util.spec_from_file_location('bound_runtime',project/'tools/runtime_manifest.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    module.verify_mature_export_exclusions(project);paths=module.runtime_paths(project)
    need(len(paths)==identity['runtime'],'Runtime count differs')
    runtime={'build':identity['build'],'engine':ENGINE,'source_sha256':{p.relative_to(project).as_posix():sha(p) for p in paths}}
    digest=hashlib.sha256()
    for name in sorted(runtime['source_sha256']):
        data=(project/name).read_bytes()
        if name=='scripts/rules.gd':
            need(re.findall(rb'const BUILD_ID = "([^"]*)"',data)==[identity['build'].encode()],'Rules identity differs')
            data=re.sub(rb'const BUILD_ID = "[^"]*"',b'const BUILD_ID = "normalized"',data)
        digest.update(name.encode());digest.update(b'\0');digest.update(data)
    need('vc-'+digest.hexdigest()[:12]==identity['build'],'Derived runtime identity differs')
    work.mkdir(mode=0o700);dest=work/'project';shutil.copytree(project,dest)
    archive=work/'source.zip'
    with zipfile.ZipFile(archive,'x',compression=zipfile.ZIP_STORED) as z:
        for name in sorted(files):
            info=zipfile.ZipInfo(name,date_time=(2026,1,1,0,0,0));info.create_system=3;info.external_attr=0o100644<<16
            with (dest/name).open('rb') as source,z.open(info,'w') as target:shutil.copyfileobj(source,target,1024*1024)
    runtime_sha=hashlib.sha256(json.dumps(runtime,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    suite='tests/map80_contract.gd';suite_sha=files[suite]['sha256'];report='OUTPUT/not-invoked.json'
    contract=dict(format='JSON object',must_be_new_file_from_this_run=True,process_exit_code=0,minimum_rows=1,rows_field='checks',row_verdict=dict(key='pass',equals=True,type='boolean'),count_equations=['passed == len(checks)','failed == 0'],required_integer_fields=dict(passed=dict(minimum=1),failed=dict(equals=0)),required_external_receipt=dict(candidate_build=identity['build'],runtime_manifest_sha256=runtime_sha,suite_sha256=suite_sha,require_process_and_output_hash_binding=True))
    manifest=dict(candidate=identity['build'],engine_expected=ENGINE,execution_enabled=False,files=list(files.values()),runtime_manifest=dict(inputs=len(paths),sha256=runtime_sha),public_runtime_descriptor=runtime,suites=[dict(name='unused_map_descriptor',script=suite,script_sha256=suite_sha,argv=['GODOT','--headless','--path','PROJECT','--script','res://'+suite,'--',report],report=report,report_contract=contract)])
    dump(work/'import-manifest.json',manifest)
    project_files={n:v['sha256'] for n,v in files.items()}
    generated=sorted(n+'.uid' for n in files if n.endswith('.gd') and n+'.uid' not in files)
    for shader in ('assets/mature/shaders/building_damage_soot.gdshader','assets/mature/menu/menu_backdrop.gdshader'):
        if shader in files and shader+'.uid' not in files:generated.append(shader+'.uid')
    lock=dict(schema='vc-web-export-v1',reviewed_for_execution=True,source_commit=SOURCE,game_tree=identity['tree'],build=identity['build'],godot_sha256=ENGINE_SHA,web_release_sha256=TEMPLATE_SHA,runner_sha256=sha(ROOT/'ci'/identity['runner']),owned_process_sha256=sha(ROOT/'ci/owned_process.py'),source_archive_sha256=sha(archive),import_manifest_sha256=sha(work/'import-manifest.json'),import_adapter_sha256=sha(ROOT/'ci/guarded_manifest_ci.py'),project_files=project_files,allowed_generated_uid_files=sorted(generated),output_files=OUTPUT_FILES,diagnostic_only=side=='diagnostic',artifact_kind='controlled-building-visual-review' if side=='diagnostic' else 'tested-building-product-candidate')
    if side=='product':
        lock['startup_identity_sha256']=sha(ROOT/'ci/startup_identity.py')
        lock.update(contracts_reviewed_for_execution=True,contracts_stop_reviewed_for_execution=True,contracts_consolidated_reviewed_for_execution=True,military_reviewed_for_execution=True,faction_reviewed_for_execution=True,building_reviewed_for_execution=True)
        for prefix,roles in {
            'contracts':{'runner':'run_contracts.py','supervisor':'run_logic.py','validator':'validate_contracts.py','names':'check_contract.json'},
            'military':{'runner':'run_military.py','supervisor':'run_logic.py','validator':'validate_military.py','names':'military_contract.json'},
            'faction':{'runner':'run_faction.py','supervisor':'run_logic.py','validator':'validate_faction.py'},
            'building':{'runner':'run_building_contracts.py','supervisor':'run_logic.py','validator':'validate_building_contracts.py'},
        }.items():
            for role,name in roles.items():lock[prefix+'_'+role+'_sha256']=sha(ROOT/'ci'/name)
        lock['faction_harness_sha256']=sha(project/'tests/faction_publish_contract.gd')
        lock['building_harness_sha256']={name:sha(ROOT/'ci/building-fixtures'/(name+'.gd') if name.startswith('building_damage_') else project/'tests'/(name+'.gd')) for name in ('advanced_building_visuals','advanced_building_observation','construction_visual','building_damage_component','building_damage_projection','map80_sparse_memory')}
    if side=='product':
        lock['latest_runner_sha256']=sha(ROOT/'ci/run_latest_contracts.py')
        lock['latest_validator_sha256']=sha(ROOT/'ci/validate_latest_contracts.py')
        lock['latest_harness_sha256']={n:sha(project/'tests'/(n+'.gd')) for n in ('material_contract','continuous_training_contract','resource_visual_contract','compact_click_contract','compact_move_runtime','hold_box_contract','hold_box_phone','contextual_routed_touch','wide_click_contract','skirmish_policy_contract','resource_polish_contract','normal_probe','army_composition_contract','army_recruitment_integration','army_formation_contract','army_formation_integration','home_defense_contract','home_defense_integration','military_technology_contract','military_tech_worker_recovery_contract','military_tech_lifecycle_contract','worker_safety_contract','worker_safety_cargo_contract','control_point_contract','control_point_menu_contract','rest_recovery_contract','field_manual_contract','scout_frontier_contract','resolved_attack_goal_contract','placement_sight_contract','idle_army_contract','workforce_contract','production_overview_contract','repair_dispatch_contract','construction_dispatch_contract','repair_layout_contract','unit_type_selection_contract','retry_gather_contract','context_manual_contract','training_batch_contract','desktop_stop_scroll_contract','wounded_retreat_contract','wounded_retreat_journey','clear_build_site_contract','idle_gather_dispatch_contract','shortcut_categories_contract','clear_production_exit_contract','blocked_workers_contract','building_attention_contract','farm_dispatch_contract','vacant_farms_contract','damage_feedback_contract','supply_race_contract','siege_effect_contract','order_routes_contract','full_tutorial_contract','battle_timeline_contract','fortress_contract','siege_repair_contract','cavalry_grip_contract','siege_visual_contract','horse_visual_contract','rider_armour_contract','siege_tactics_contract','army_roster_contract','pinned_menu_contract','combat_veterancy_contract','battle_speed_contract','arrow_effect_contract','target_priority_contract','tower_focus_contract','siege_challenge_contract','checkpoint_codec_contract','checkpoint_continuation_contract','checkpoint_menu_contract','siege_challenge_engagement_contract','army_recruitment_contract','army_recruitment_menu_contract','ui_glyph_coverage_contract','escort_policy_contract','escort_integration_contract','gather_assignment_contract','workforce_reassign_contract','ai_resource_outpost_contract','ai_army_recovery_contract','ai_infrastructure_repair_contract','batch_repair_dispatch_contract','batch_construction_dispatch_contract','player_scout_dispatch_contract','ai_gather_load_contract','resource_lifecycle_contract','model_catalogue_contract','ai_siege_response_contract','frontier_expedition_contract','expedition_checkpoint_contract','checkpoint_preservation_contract','checkpoint_restore_feedback_contract','checkpoint_backups_contract','battle_selection_contract','frontier_escort_contract','escort_menu_contract','escort_storage_boundary_contract','ai_economic_raid_contract','home_defense_allocation_contract','home_defense_allocation_integration','raid_reinforcement_contract','battlefield_layout_contract','battlefield_menu_contract','checkpoint_layout_contract','compact_battle_hud_contract','tactical_route_contract','tactical_route_input_contract','construction_return_contract','construction_return_journey','frontline_supply_contract','frontline_supply_journey','garrison_contract','garrison_checkpoint_contract','garrison_natural_journey','ai_worker_safety_contract','ai_worker_safety_checkpoint_contract','ai_evacuation_natural_journey','trade_ledger_contract','trade_checkpoint_contract','resource_trade_contract','resource_trade_input_contract','resource_trade_natural_journey','wall_visual_contract','wall_checkpoint_contract','wall_breach_contract','wall_construction_contract','wall_contact_contract','wall_line_contract','ai_fortify_contract','ai_archer_spacing_contract','minimap_navigation_contract','minimap_touch_ownership_contract','ai_difficulty_contract','difficulty_menu_contract','guided_tutorial_contract','auto_checkpoint_contract','aftermath_inspection_contract','range_reference_contract','siege_target_priority_contract','escort_batch_contract','army_box_selection_contract','army_withdraw_contract','breach_mission_contract','breach_menu_contract','breach_mission_journey','touch_navigation_contract','pinch_intent_contract','command_icons_contract','touch_camera_continuity_contract','friendly_pick_routed_contract','batch_siege_repair_contract','siege_service_journey','repair_contact_route_contract','battle_navigation_contract','production_wait_navigation_contract','unit_yaw_checkpoint_contract','production_shortfall_rules_contract','production_shortfall_contract','ai_traffic_escape_contract','command_portraits_contract','contextual_construction_resume_contract','military_route_feedback_contract','blocked_combat_contract','ai_shelter_delivery_contract','tutorial_fold_contract','ai_food_feasibility_contract','ai_idle_yield_contract','ai_shelter_staffing_contract','licensed_resource_contract','ai_queued_yield_contract','simultaneous_attack_display_contract','ai_building_spacing_contract','bush_fruit_contract','compact_initial_camera_contract','compact_camera_routes_contract','ai_gather_contact_contract','ai_worker_route_risk_contract','fog_inward_edge_contract','fog_unit_tile_contract','ai_muster_fallback_contract','measured_battle_topbar_contract','attack_readability_combined_contract','attack_readability_combined_lifecycle','attack_readability_combined_fog','food_farm_shortcut_contract','original_ground_albedo_contract','command_context_scroll_contract','command_context_lifecycle_contract','command_context_menu_lifecycle_contract','mineral_trade_policy_contract','mineral_trade_runtime_contract','mineral_trade_input_contract','trade_icon_classification_contract','command_mode_scroll_contract','command_mode_paid_flow_contract','tactical_advance_phone','iron_crossroads_geometry','iron_crossroads_menu','iron_crossroads_natural_journey','milestone_retention_contract','match_milestone_journey','campaign_progress_contract','campaign_natural_journey','campaign_progress_store_contract','landscape_hud_contract','objective_camera_route_contract','escort_outpost_boundary_contract','forward_depot_contract','forward_depot_natural_journey','river_terrain_contract','river_siege_travel_contract','river_touch_crossing_contract','production_egress_contract','landscape_setup_briefing_contract','campaign_contention_contract','army_ground_context_contract','upgrade_command_icons_contract','town_research_bookmarks_contract','town_research_lifecycle_contract')}
    dump(work/'export-lock.json',lock)
    (work/'pins.env').write_text('ARCHIVE_SHA='+lock['source_archive_sha256']+'\nMANIFEST_SHA='+lock['import_manifest_sha256']+'\n')
    dump(work/'source-attestation.json',dict(side=side,build=identity['build'],game_tree=identity['tree'],source_commit=SOURCE,workflow_commit=git('rev-parse','HEAD'),source_files=len(files),runtime_inputs=len(paths),source_archive_sha256=sha(archive),import_manifest_sha256=sha(work/'import-manifest.json'),diagnostic_only=side=='diagnostic',engine_executed=False))
    return {'side':side,'build':identity['build'],'game_tree':identity['tree'],'source_files':len(files),'engine_executed':False}


def main():
    parser=argparse.ArgumentParser();parser.add_argument('phase',choices=['prepare','engine']);parser.add_argument('--side',choices=SIDES,default='product');parser.add_argument('--work',type=Path,required=True);args=parser.parse_args();admitted()
    if args.phase=='prepare':print(json.dumps(prepare(args.side,args.work)))
    else:
        import official_download as download
        need(args.side=='product' and (args.work/'export-lock.json').is_file(),'Product source preparation required')
        download.download(download.ENGINE_URL,args.work/'engine.zip');download.safe_extract(args.work/'engine.zip',{download.ENGINE_NAME:ENGINE_SHA},args.work/'engine',max_total=256*1024*1024,max_member=256*1024*1024)
        (args.work/'engine'/download.ENGINE_NAME).chmod(0o755)
        print('Pinned official engine prepared without launch')


if __name__=='__main__':main()
