"""Fixed, bounded visibility lifecycle report contract; no execution."""
from pathlib import Path
import validate_contracts as strict

SUITE='visibility_once_lifecycle'
FIXTURE='tests/visibility_once_lifecycle.gd'
FIXTURE_SHA='db63648a075e142d695e6c758b74389605e84eedbc2133945e14f83a1b0cb2fd'
PROJECTION_LABELS=['own selected damaged', 'own deselected healed', 'own unselected damaged', 'paused', 'game_over', 'application_suspended', 'application_focused', 'enemy observed damaged', 'enemy hidden mutated', 'enemy reobserved', 'enemy hidden dead', 'own dead', 'enemy observed dead', 'pine unseen', 'pine observed', 'pine remembered hidden mutation', 'pine reobserved', 'pine hidden dead remembered', 'pine visible empty', 'oak unseen', 'oak observed', 'oak remembered hidden mutation', 'oak reobserved', 'oak hidden dead remembered', 'oak visible empty', 'berry unseen', 'berry observed', 'berry remembered hidden mutation', 'berry reobserved', 'berry hidden dead remembered', 'berry visible empty', 'stone unseen', 'stone observed', 'stone remembered hidden mutation', 'stone reobserved', 'stone hidden dead remembered', 'stone visible empty', 'iron unseen', 'iron observed', 'iron remembered hidden mutation', 'iron reobserved', 'iron hidden dead remembered', 'iron visible empty', 'orphan retired']
SOURCE_SHAS={'baseline':'0596a611029fc7c8867ab4f18e73709aa0f982f6e47909649ee3e96e9dd51d0f','candidate':'32b16b322d99e4922eb421143714b16a65fb35ad6088114132fe92b840aa0dfc'}
SOURCE_NAMES=('scripts/game.gd','scripts/faction_view.gd','scripts/observed_character_presenter.gd','scripts/action_character.gd','scripts/observed_occlusion.gd','scripts/building_damage_presenter.gd','scripts/construction_visual.gd')
SCOPE='Controlled actual-engine signals, final visibility and observation lifecycle. Not rendered pixels, ordinary gameplay or performance.'
need=strict.need

def validate(report,lock,names):
    keys={'suite','build','scope','variant','source_sha256','fixture_sha256','engine','passed','failure_count','checks','signal_batches','signal_samples','projection_states','signal_sample_limit','signal_events_seen'}
    need(type(report) is dict and set(report)==keys,'Unexpected visibility fields')
    need(report['suite']==SUITE and report['build']==lock['build'] and report['scope']==SCOPE,'Wrong visibility identity/scope')
    variant=report['variant'];need(variant in SOURCE_SHAS,'Unknown visibility variant')
    need(lock['project_files']['scripts/game.gd']==SOURCE_SHAS[variant],'Visibility source variant mismatch')
    need(lock['project_files'][FIXTURE]==report['fixture_sha256']==FIXTURE_SHA,'Unreviewed visibility fixture')
    need(report['source_sha256']=={n:lock['project_files'][n] for n in SOURCE_NAMES},'Visibility source hashes differ')
    checks=report['checks'];need(type(names) is list and len(names)==124 and len(set(names))==124,'Unreviewed visibility names')
    need(type(checks) is list and len(checks)==124,'Missing visibility checks')
    need(all(type(x) is dict and set(x)=={'name','passed'} and type(x['name']) is str and x['passed'] is True for x in checks),'Failed/malformed visibility check')
    need([x['name'] for x in checks]==names,'Visibility check order/name mismatch')
    need(type(report['passed']) is int and report['passed']==124 and type(report['failure_count']) is int and report['failure_count']==0,'Visibility count failure')
    engine=report['engine'];need(type(engine) is dict and all(engine.get(k)==v for k,v in [('major',4),('minor',6),('patch',3),('status','stable'),('build','official')]),'Wrong reported engine')
    batches=report['signal_batches'];need(type(batches) is list and len(batches)==16,'Missing visibility signal batches')
    expected_phases=[n.removesuffix(' real root signal count') for n in names if n.endswith(' real root signal count')]
    need([x.get('phase') for x in batches]==expected_phases,'Signal phase order differs')
    for batch in batches:
        need(type(batch) is dict and set(batch)=={'phase','repeats','counts'},'Wrong signal batch schema')
        need(type(batch['repeats']) is int and batch['repeats']==(3 if batch['phase'] in ('own selected damaged','enemy observed damaged') else 2),'Wrong repeat count')
        counts=batch['counts'];need(type(counts) is dict and all(type(k) is str and type(v) is int and v>0 for k,v in counts.items()),'Invalid signal counts')
        need((not counts) if variant=='candidate' else bool(counts),'Stable signal expectation failed')
    samples=report['signal_samples'];need(type(samples) is list and len(samples)<=128 and report['signal_sample_limit']==128,'Signal sample bound differs')
    need(type(report['signal_events_seen']) is int and len(samples)<=report['signal_events_seen']<=100000,'Invalid signal event count')
    for x in samples:
        need(type(x) is dict and set(x)=={'phase','node','visible','in_tree'} and type(x['phase']) is str and type(x['node']) is str and type(x['visible']) is bool and type(x['in_tree']) is bool,'Invalid signal sample')
    states=report['projection_states'];need(type(states) is list and len(states)==44,'Missing public projection states')
    need([x.get('label') for x in states]==PROJECTION_LABELS,'Public projection label/order mismatch')
    allowed={'label','record','authority_visible','authority_in_tree','ring','bar','position','fill','proxy_visible','proxy_in_tree','proxy_bar','remembered','body_rotation','materials','construction_stage','clip','pose'}
    for x in states:
        need(type(x) is dict and {'label','record','authority_visible','authority_in_tree','ring','bar'}<=set(x)<=allowed,'Unexpected projection fields')
        need(type(x['label']) is str and type(x['record']) is dict,'Invalid public projection')
        need(all(type(x[k]) is bool for k in ('authority_visible','authority_in_tree','ring')) and (x['bar'] is None or type(x['bar']) is bool),'Invalid public visibility')
    return report

def read_log(path,lock,names):
    path=Path(path);need(path.is_file() and not path.is_symlink() and 0<path.stat().st_size<=16*1024*1024,'Invalid visibility log')
    rows=[line for line in path.read_text(encoding='utf-8').splitlines() if strict.is_report_line(line)]
    need(len(rows)==1 and len(rows[0].encode())<=128*1024,'Missing/duplicate/oversized visibility JSON')
    return validate(strict.parse_json(rows[0]),lock,names)
