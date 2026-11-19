extends SceneTree
const Progress=preload("res://scripts/campaign_progress.gd")
var checks=[]
func ck(n,x):checks.append({"name":n,"passed":bool(x)})
func _initialize():call_deferred("run")
func frames():
 for _i in 4:await process_frame
func push(menu,id):
 menu.buttons.get_node(id).pressed.emit()
 await frames()
func write(path,s):
 var f=FileAccess.open(path,FileAccess.WRITE)
 f.store_string(s);f.close()
func shell(path):
 var m=load("res://main_menu.tscn").instantiate()
 m.campaign_progress_path=path
 root.add_child(m)
 return m
func run():
 root.size=Vector2i(390,844)
 var tag="/tmp/v133-progress-"+str(Time.get_ticks_usec())
 var path=tag+"-campaign.json"
 var other=[tag+"-manual",tag+"-expedition",tag+"-auto",tag+"-history"]
 for p in other:write(p,"unchanged isolated other data")
 var empty=Progress.read(path)
 ck("empty begins zero without creating any storage",empty.ok and empty.completed==0 and empty.revision==0 and not FileAccess.file_exists(path))
 ck("cannot skip an unearned chapter",not Progress.save(empty,2,false,path).ok and not FileAccess.file_exists(path))
 var one=Progress.save(empty,1,false,path)
 ck("completion one atomically reads back with revision one",one.ok and one.completed==1 and one.revision==1 and Progress.read(path)==one)
 var raw=FileAccess.get_file_as_string(path)
 ck("stale writer cannot replace newer progress",not Progress.save(empty,1,false,path).ok and FileAccess.get_file_as_string(path)==raw)
 var invalid=tag+"-corrupt.json"
 write(invalid,'{"schema":1,"revision":1,"completed":3}')
 var decoded_bad=Progress.read(invalid)
 ck("invalid prior bytes preserved and diagnosed",not decoded_bad.ok and not Progress.save(empty,1,false,invalid).ok and FileAccess.get_file_as_string(invalid)=='{"schema":1,"revision":1,"completed":3}')
 ck("revision and count types cannot be strings floats or bool",not Progress._decode('{"schema":1,"revision":3,"completed":true}').ok and not Progress._decode('{"schema":1,"revision":"3","completed":2}').ok and not Progress._decode('{"schema":1,"revision":3,"completed":1.5}').ok)
 var m=shell(path);await frames()
 ck("reopening reads real prior completion but not in-progress game",m.campaign_unlocked==1 and not is_instance_valid(m.match_node))
 await push(m,"StartMatchButton");await push(m,"CampaignMenuButton")
 ck("campaign describes browser/desktop chapter-only retention",m.description.text.contains("未完成戰場不會恢復") and m.description.text.contains("已完成 1 / 3"))
 await push(m,"RestartCampaignButton");await push(m,"BackButton")
 ck("restart preview cancel never writes progress",m.campaign_unlocked==1 and FileAccess.get_file_as_string(path)==raw)
 await push(m,"CampaignChapterButton");await push(m,"LaunchMatchButton")
 var g=m.match_node
 g.set_process(false);g.test_mode=true
 g._submit("surrender");g._tick(g.Rules.TICK)
 ck("normal defeat does not write or unlock anything",g.outcome=="defeat" and m.campaign_unlocked==1 and FileAccess.get_file_as_string(path)==raw)
 g.end_actions.get_node("ReplayMatchButton").pressed.emit();await frames()
 g=m.match_node;g.set_process(false);g.test_mode=true
 # Controlled actual terminal event for the storage branch; natural
 # commands and a genuine earned first win are a separate exact test.
 g.siege_challenge.complete=true;g._check_end()
 var two=Progress.read(path)
 ck("qualifying terminal guard updates only campaign progress",g.outcome=="victory" and g.end_reason=="waves_defended" and two.ok and two.completed==2 and two.revision==2 and m.campaign_unlocked==2)
 m._observe_campaign_result(g)
 ck("duplicate old terminal signal does not add a write",Progress.read(path)==two and m.campaign_unlocked==2)
 g.end_setup_button.pressed.emit();await frames()
 await push(m,"BackButton");await push(m,"RestartCampaignButton")
 ck("explicit restart only writes after confirmed launch",Progress.read(path)==two)
 await push(m,"LaunchMatchButton")
 g=m.match_node;g.set_process(false);g.test_mode=true
 var reset=Progress.read(path)
 ck("confirmed restart increments revision instead of deleting old identity",reset.ok and reset.completed==0 and reset.revision==3 and m.campaign_unlocked==0 and g.campaign_chapter==0)
 ck("stale expected prior cannot undo explicit reset",not Progress.save(two,3,false,path).ok and Progress.read(path)==reset)
 ck("manual expedition auto and history sentinels remain byte exact",other.all(func(p):return FileAccess.get_file_as_string(p)=="unchanged isolated other data"))
 m.free();await frames()
 m=shell(invalid);await frames()
 ck("unavailable progress permits session only and does not load invalid data",m.campaign_unlocked==0 and not m.campaign_storage.ok and m._campaign_storage_label().contains("只限本次遊戲"))
 await push(m,"StartMatchButton");await push(m,"CampaignMenuButton");await push(m,"CampaignChapterButton");await push(m,"LaunchMatchButton")
 g=m.match_node;g.set_process(false);g.test_mode=true
 g.breach_mission.stage=2;g._check_end()
 ck("genuine rules can progress in session despite failed persistence",g.outcome=="victory" and m.campaign_unlocked==1 and g.end_body.text.contains("只限本次遊戲") and not m.campaign_storage.ok)
 ck("never replace corruption even after later terminal success",FileAccess.get_file_as_string(invalid)=='{"schema":1,"revision":1,"completed":3}')
 m.free();await frames()
 for x in other+[path,invalid]:DirAccess.remove_absolute(x)
 var failed=checks.filter(func(a):return not a.passed).size()
 print(JSON.stringify({"suite":"campaign_progress_store_contract","checks":checks,"failed":failed,"scope":"Dedicated native storage, stale malformed reset fail closed, real defeat and controlled qualifying terminal boundaries; not browser persistence or natural match evidence."}))
 quit(1 if failed else 0)
