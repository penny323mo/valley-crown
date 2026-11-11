#!/usr/bin/env python3
"""Read-only headless JSON contract. No rendering/phone/realtime acceptance."""
import math

def require(ok, message):
    if not ok:
        raise ValueError(message)


def finite_number(value):
    return type(value) in (int, float) and math.isfinite(value)


def validate(report, lock):
    require(type(report) is dict and report.get('report_type') == 'vc-headless-combat-logic-v1', 'Wrong report schema')
    require(report.get('passed') is True and report.get('stop_reason') == 'scenario_completed', 'Scenario incomplete')
    require(report.get('scope') == 'headless_simulated_gameplay_logic' and report.get('build') == lock['build'], 'Wrong logic scope/build')
    omitted = {'rendering', 'screenshots', 'Web', 'physical touch', 'iPhone', 'realtime', 'performance'}
    require(omitted <= set(report.get('not_verified', [])), 'Limitations omitted')
    frames = report.get('checkpoints')
    require(type(frames) is list and len(frames) == report.get('checkpoint_count') == 10, 'Incomplete checkpoint count')
    previous_usec = previous_frame = previous_tick = -1
    for frame in frames:
        require(frame.get('checkpoint_kind') == 'headless_public_state' and frame.get('display') == 'headless', 'Not headless state evidence')
        require(not any(k in frame for k in ('image', 'image_sha256', 'framebuffer', 'animation_poses')), 'Unexpected visual evidence claim')
        require(frame.get('build') == lock['build'] and frame.get('game_sha256') == lock['project_files']['scripts/game.gd']
                and frame.get('rules_sha256') == lock['project_files']['scripts/rules.gd'], 'Source mismatch')
        require(frame.get('engine_time_scale') == 1 and frame.get('logical_viewport') == [390, 844], 'Clock or logical viewport differs')
        require(frame.get('economy_audit_ok') is True, 'Economy audit failed')
        usec, process, tick = (frame.get(k) for k in ('monotonic_usec', 'process_frame', 'game_tick'))
        seconds = frame.get('game_seconds')
        require(all(type(x) is int for x in (usec, process, tick)), 'Invalid checkpoint counters')
        require(usec > previous_usec and process > previous_frame and tick > previous_tick, 'Nonincreasing checkpoint counters')
        require(finite_number(seconds) and math.isclose(seconds, tick * .05, rel_tol=1e-6, abs_tol=1e-6), 'Game clock differs from ordinary fixed ticks')
        require(frame['public_state'].get('tick') == tick and math.isclose(frame['public_state'].get('time', -1), seconds, abs_tol=1e-6), 'Snapshot clock mismatch')
        for unit in frame['encounter'].get('visible_enemy_units', []):
            require(unit.get('team') == 1 and unit.get('owned') is False and unit.get('remembered') is False, 'Nonpublic enemy observation')
        target = frame['encounter'].get('target', {})
        if target:
            require(target.get('remembered') is False and target.get('team') == 1, 'Remembered or wrong enemy target')
        previous_usec, previous_frame, previous_tick = usec, process, tick
    return validate_scenario(report, lock)


def validate_scenario(report, lock):
    frames=report['checkpoints']
    if True:
        labels=['scout-before-expedition','scout-crossing-open-ground','scout-revealing-midfield','rival-revealed-before-attack','scout-ordered-to-attack','first-confirmed-hit','second-confirmed-hit','third-confirmed-hit','retreat-command-accepted','scout-retreated-after-real-damage']
        require([f['label'] for f in frames]==labels, 'Combat frame coverage differs')
        require(report.get('scenario')=='scout_reveal_attack_damage_retreat', 'Combat scenario differs')
        names=['ordinary opening scout exists','no enemy unit is initially visible','visible tutorial skip is available','tutorial explicitly skipped not completed','scout departs through normal movement','scout naturally reaches midfield','rival villager becomes currently visible','attack target is live public enemy','visible target can be normally picked','normal attack command reaches authority','first-confirmed-hit','first-confirmed-hit has public attack cue','second-confirmed-hit','second-confirmed-hit has public attack cue','third-confirmed-hit','third-confirmed-hit has public attack cue','retreat replaces attack through normal queue','living scout retreats four world units']
        checks=report.get('checks',[])
        require([r.get('name') for r in checks]==names and all(r.get('pass') is True for r in checks), 'Combat assertions missing or failed')
        require(report.get('passed_checks')==len(names) and report.get('failed_checks')==0, 'Combat check counts differ')
        commands=report.get('commands',[])
        require([r.get('kind') for r in commands]==['scout_ground_move','attack_visible_enemy','retreat_ground_move'], 'Combat command provenance differs')
        scout=report.get('scout');target=report.get('target')
        require(type(scout) is int and type(target) is int and scout>=0 and target>=0 and scout!=target, 'Invalid combat IDs')
        require(commands[0].get('target')==commands[2].get('target')==-1 and commands[1].get('target')==target and commands[1].get('target_was_visible') is True, 'Hidden entity targeting or changed target')
        require(commands[0].get('worker')==commands[1].get('scout')==commands[2].get('scout')==scout, 'Scout command identity differs')
        states=[f.get('public_state',{}) for f in frames];encounters=[f.get('encounter',{}) for f in frames]
        require(all(s.get('paused') is False and s.get('game_over') is False and s.get('build')==lock['build'] for s in states), 'Interrupted or wrong game state')
        require(all(s.get('food')==150 and s.get('wood')==200 and s.get('population')==6 and s.get('trained')==0 and s.get('built')==0 for s in states), 'Unexpected player resource or entity manipulation')
        require(frames[0].get('tutorial_skipped') is False and all(f.get('tutorial_skipped') is True for f in frames[1:]), 'Tutorial skip labeling differs')
        require(encounters[0].get('visible_enemy_units')==[] and encounters[0].get('target')=={}, 'Target was not initially hidden')
        ours=[e.get('scout',{}) for e in encounters]
        require(all(u.get('id')==scout and u.get('kind')=='scout' and u.get('owned') is True and u.get('alive') is True and 0<u.get('hp',0)<=50 for u in ours), 'Existing live scout identity differs')
        before=encounters[3].get('target',{})
        require(before.get('id')==target and before.get('kind')=='villager' and before.get('owned') is False and before.get('team')==1 and before.get('remembered') is False and before.get('hp')==report.get('enemy_hp_before')==commands[1].get('target_hp_before'), 'Pre-attack observation differs')
        require(frames[3]['game_tick']<=commands[1]['tick']<=frames[4]['game_tick'], 'Attack order outside recorded observation')
        health=[before['hp']]
        for i,damage in ((5,4),(6,8),(7,12)):
            theirs=encounters[i].get('target',{})
            require(theirs.get('id')==target and theirs.get('team')==1 and theirs.get('remembered') is False and theirs.get('alive') is True, 'Damage target not currently visible')
            require(theirs.get('hp',0)>0 and theirs['hp']==before['hp']-damage, 'Exact four-HP hit milestone differs')
            require(ours[i].get('state')=='attack' and ours[i].get('target')==target and ours[i].get('visual_attack_tick',-1)>=commands[1]['tick'] and theirs.get('visual_hit_tick',-1)>=commands[1]['tick'], 'Public hit/attack cue absent')
            require(ours[i]['visual_attack_tick'] <= frames[i]['game_tick'] and theirs['visual_hit_tick'] <= frames[i]['game_tick'], 'Future attack/hit cue')
            health.append(theirs['hp'])
        require(all(a>b for a,b in zip(health,health[1:])), 'HP did not fall at distinct hit milestones')
        require(all(ours[i+1]['visual_attack_tick']-ours[i]['visual_attack_tick']>=30 for i in (5,6)), 'Damage milestones lack separate attack releases')
        require(ours[8].get('state')==ours[9].get('state')=='move' and ours[8].get('target')==ours[9].get('target')==-1, 'Retreat did not replace attack')
        start=commands[2].get('start');end=ours[9]['position']
        require(type(start) is list and len(start)==len(end)==3 and math.dist(start,end)>=4, 'Scout did not actually retreat')
        require(math.dist(ours[0]['position'],ours[2]['position'])>20 and frames[2]['game_tick']-commands[0]['tick']>=200, 'Natural scouting progression absent')
    return {"scenario": report["scenario"], "damage_milestones": [4, 8, 12], "checkpoints": len(frames)}
