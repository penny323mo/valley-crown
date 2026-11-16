extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
const Store=preload("res://scripts/expedition_checkpoint_store.gd")
const Ordinary=preload("res://scripts/checkpoint_store.gd")
var checks=[]
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func make_game():
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="expedition";root.add_child(g);g.set_process(false);g.test_mode=true
 return g
func run():
 var g=make_game();await process_frame
 check("initial mission validates",Codec.capture_result(g).ok)
 var before=Codec.capture(g)
 var h=make_game();await process_frame
 check("initial mission restores",Restore.apply(h,before))
 check("initial mission authoritative fields unchanged",Codec.capture(h)==before)
 h.free()
 for phase in [1,2]:
  g.frontier_expedition.stage=phase;g.frontier_expedition.stage_ticks=[1] if phase==1 else [1,2];g.tick_count=3;g.game_time=.15
  var stage_data=Codec.capture_result(g)
  h=make_game();await process_frame
  check("pre-assault stage roundtrip "+str(phase),stage_data.ok and Restore.apply(h,stage_data.data) and Codec.capture(h)==stage_data.data)
  h.free()
 # Controlled mission boundary fixture, not a claimed natural campaign playthrough.
 g.tick_count=100;g.game_time=5;g._kill(g._get_entity(g.frontier_expedition.outpost_id))
 g.frontier_expedition.stage=3;g.frontier_expedition.stage_ticks=[20,40,80];g.frontier_expedition.counter_due=680
 g.frontier_expedition.trained=2;g.frontier_expedition.supplied=100000
 g.paused=true
 check("paused countdown saves to independent slot",Store.save_slot(g,"user://test_exp_slot.bin").ok)
 var read=Store.read_slot(g.Rules.BUILD_ID,"user://test_exp_slot.bin")
 check("countdown reads with exact due tick",read.ok and read.data.modules.frontier_expedition.counter_due==680)
 if not read.ok:print(read);quit(1);return
 h=make_game();await process_frame
 check("countdown restores",Restore.apply(h,read.data))
 check("restore stays paused with exact countdown",h.paused and h.tick_count==100 and h.frontier_expedition.counter_due==680)
 # Both ordinary-tick branches should generate precisely the same single wave.
 g.paused=false;h.paused=false
 for i in 600:g._tick(.05);h._tick(.05)
 check("counter launched normally once on both branches",g.frontier_expedition.counter_ids.size()==6 and h.frontier_expedition.counter_ids==g.frontier_expedition.counter_ids)
 check("ordinary continuation after restore is identical",Codec.capture(h)==Codec.capture(g))
 h.free()
 # Block all authored staging slots with real buildings in this isolated fixture.
 var blocked=make_game();await process_frame
 blocked._kill(blocked._get_entity(blocked.frontier_expedition.outpost_id))
 blocked.tick_count=680;blocked.game_time=34
 blocked.frontier_expedition.stage=3;blocked.frontier_expedition.stage_ticks=[20,40,80];blocked.frontier_expedition.counter_due=680
 for z in 8:
  for x in 8:blocked._spawn("house",1,blocked.FrontierExpedition.STAGING+Vector3(x*2,0,-z*2),true)
 blocked._navigation_rebuild();blocked._update_frontier_expedition()
 check("blocked staging delays wave without marking launched",not blocked.frontier_expedition.counter_launched)
 var blocked_data=Codec.capture_result(blocked)
 h=make_game();await process_frame
 check("blocked staging state restores",blocked_data.ok and Restore.apply(h,blocked_data.data))
 var blocked_next=h.next_id;h._update_frontier_expedition()
 check("restored blocked staging does not duplicate or overlap spawn",h.next_id==blocked_next and not h.frontier_expedition.counter_launched and h.frontier_expedition.counter_due==680)
 for ent in h.entities:
  if ent.kind=="house" and ent.team==1:h._kill(ent)
 h._navigation_rebuild();h._update_frontier_expedition()
 check("restored blocked wave launches once when space clears",h.frontier_expedition.counter_launched and h.frontier_expedition.counter_ids.size()==6)
 var once=h.next_id;h._update_frontier_expedition()
 check("unblocked restored wave cannot launch twice",h.next_id==once)
 blocked.free();h.free()
 var counter=g.frontier_expedition.counter_ids
 g._kill(g._get_entity(counter[0]));g.paused=true
 var partial=Codec.capture_result(g)
 check("partial dead counter validates",partial.ok)
 h=make_game();await process_frame
 check("partial dead counter restores",Restore.apply(h,partial.data))
 var next=h.next_id;var ids=h.frontier_expedition.counter_ids.duplicate()
 for i in 20:h._update_frontier_expedition()
 check("restoration cannot duplicate launched wave",h.next_id==next and h.frontier_expedition.counter_ids==ids and not h._get_entity(ids[0]).alive)
 for id in ids:h._kill(h._get_entity(id))
 h._update_frontier_expedition()
 check("restored remaining wave death advances final objective",h.frontier_expedition.stage==4)
 check("final objective checkpoint validates",Codec.capture_result(h).ok)
 var mutated=partial.data.duplicate(true);mutated.modules.frontier_expedition.counter_ids[1]=mutated.modules.frontier_expedition.counter_ids[0]
 check("duplicate counter id rejected",not Codec.validate(mutated))
 mutated=partial.data.duplicate(true);mutated.modules.frontier_expedition.counter_due+=1
 check("counter clock mismatch rejected",not Codec.validate(mutated))
 mutated=partial.data.duplicate(true);mutated.modules.frontier_expedition.stage=6
 check("out of range stage rejected",not Codec.validate(mutated))
 mutated=partial.data.duplicate(true);mutated.modules.frontier_expedition.counter_ids[0]=999999
 check("missing counter reference rejected",not Codec.validate(mutated))
 mutated=partial.data.duplicate(true);mutated.modules.erase("frontier_expedition")
 check("missing mission data rejected",not Codec.validate(mutated))
 mutated=partial.data.duplicate(true);mutated.modules.frontier_expedition.stage_ticks[0]=99999
 check("future stage timestamp rejected",not Codec.validate(mutated))
 check("ordinary writer continues to refuse expedition",not Ordinary.save_slot(g,"user://test_ordinary_slot.bin").ok)
 check("expedition writer cannot target actual ordinary slot",not Store.save_slot(g,Ordinary.PATH).ok)
 check("ordinary reader rejects expedition file",not Ordinary.read_slot(g.Rules.BUILD_ID,"user://test_exp_slot.bin").ok)
 var original_hash=FileAccess.get_sha256("user://test_exp_slot.bin")
 var original_stage=g.frontier_expedition.stage;g.frontier_expedition.stage=99
 check("invalid state cannot replace existing mission save",not Store.save_slot(g,"user://test_exp_slot.bin").ok and FileAccess.get_sha256("user://test_exp_slot.bin")==original_hash)
 g.frontier_expedition.stage=original_stage;g.paused=false
 check("unpaused mission cannot overwrite existing save",not Store.save_slot(g,"user://test_exp_slot.bin").ok and FileAccess.get_sha256("user://test_exp_slot.bin")==original_hash)
 g.paused=true
 check("different build rejected",not Store.read_slot("wrong","user://test_exp_slot.bin").ok)
 var f=FileAccess.open("user://test_exp_bad.bin",FileAccess.WRITE);f.store_string("bad");f.close()
 check("corrupted bytes rejected",not Store.read_slot(g.Rules.BUILD_ID,"user://test_exp_bad.bin").ok)
 g.free();h.free();await process_frame
 await menu_case()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"expedition_checkpoint_contract","checks":checks,"failed":failed,"scope":"Native isolated local slots; controlled mission boundaries and ordinary tick continuation, no private save fixtures or browser durability claim"}));quit(0 if failed==0 else 1)
func menu_case():
 var shell=load("res://scripts/main_menu.gd").new()
 shell.checkpoint_path="user://test_ordinary_preserve.bin";shell.expedition_checkpoint_path="user://test_exp_menu.bin"
 var f=FileAccess.open(shell.checkpoint_path,FileAccess.WRITE);f.store_string("ordinary sentinel");f.close()
 var hash=FileAccess.get_sha256(shell.checkpoint_path)
 root.add_child(shell);await process_frame
 shell.selected_mode="expedition";shell._replace_match();var g=shell.match_node;g.set_process(false);g.test_mode=true
 shell._open_menu();shell._show_page("checkpoint")
 check("mission menu exposes save",shell.buttons.find_child("SaveCheckpointButton",true,false)!=null)
 shell._save_checkpoint()
 check("mission save preserves ordinary file bytes",FileAccess.get_sha256(shell.checkpoint_path)==hash)
 check("mission menu exposes separate load",shell.buttons.find_child("LoadExpeditionCheckpointButton",true,false)!=null)
 shell._restore_checkpoint(true)
 check("mission load restored independently paused",shell.match_node!=g and shell.match_node.skirmish_mode=="expedition" and shell.match_node.paused)
 check("mission load preserves ordinary bytes",FileAccess.get_sha256(shell.checkpoint_path)==hash)
 var current=shell.match_node
 f=FileAccess.open(shell.expedition_checkpoint_path,FileAccess.WRITE);f.store_string("bad");f.close()
 shell._restore_checkpoint(true)
 check("failed mission load retains current game",shell.match_node==current)
 for size in [Vector2i(390,844),Vector2i(640,360)]:
  root.size=size;shell._show_page("checkpoint");await process_frame;await process_frame
  var fit=true
  for button in shell.buttons.get_children():fit=fit and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()) and button.size.y>=44
  check("separate slot controls fit "+str(size),fit)
 shell.free();await process_frame
