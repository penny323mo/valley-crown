extends SceneTree
const T=preload("res://scripts/demo_tutorial.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func touch(p,down,cancel=false,index=0):
 var e=InputEventScreenTouch.new();e.position=p;e.index=index;e.pressed=down;e.canceled=cancel;root.push_input(e);await process_frame
func run():
 root.size=Vector2i(960,640)
 var t=T.new();t.record("select");t.skip();t.resume()
 check("resume retains real achievements",t.step()==1 and not t.skipped and t.achieved.size()==1)
 check("checklist shows ten steps and current action",t.checklist(false).count("[待做]")==8 and t.checklist(false).contains("[目前] 2.") and t.checklist(false).contains("[完成] 1."))
 var resource={"id":7,"kind":"berry","category":"resource","alive":true,"owned":false,"remembered":true,"pos":Vector3(9,0,9)}
 check("locate rejects remembered resource",not t.locate({7:resource}).ok)
 resource.remembered=false
 check("locate accepts currently observed resource",t.locate({7:resource}).id==7)
 t.reset()
 var enemy={"id":9,"kind":"villager","category":"unit","alive":true,"owned":false,"remembered":false,"pos":Vector3(2,0,2)}
 check("locate rejects nonowned worker",not t.locate({9:enemy}).ok)
 var shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await process_frame
 shell._show_page("help")
 check("help discloses practice normal rules",shell.description.text.contains("不主動遠征") and shell.description.text.contains("付費建造") and shell.buttons.has_node("GuidedPracticeButton"))
 shell.buttons.get_node("GuidedPracticeButton").pressed.emit()
 check("practice entry configures not silently launches",shell.page=="setup" and shell.selected_mode=="practice" and not is_instance_valid(shell.match_node))
 shell.buttons.get_node("LaunchMatchButton").pressed.emit();await process_frame;await process_frame
 var g=shell.match_node;g.set_process(false);g.test_mode=true;g.ai_enabled=false
 check("practice launches ordinary opening",g.skirmish_mode=="practice" and g._count(0,"villager")==5 and g._count(0,"scout")==1)
 var worker=g._first(0,"villager")
 g._select([worker.id]);g.toast_time=0
 check("real selection completes first step",g.demo_tutorial.achieved.has("select"))
 g._toggle_context_details("guidance");await process_frame
 var selected=g.selected.duplicate();var commands=g.commands.duplicate(true);var mode=g.unit_command_kind
 var old_camera=g.camera_focus;var target=g.demo_tutorial.locate(g.faction_views[0].records())
 g._locate_tutorial()
 check("locate moves to known target",target.ok and g.camera_focus==target.position)
 check("locate leaves selection commands and mode intact",g.selected==selected and g.commands==commands and g.unit_command_kind==mode)
 g._locate_tutorial();check("duplicate locate idempotent without orders",g.commands==commands and g.camera_focus==target.position)
 var point=g.tutorial_locate.get_global_rect().get_center()
 g.camera_focus=old_camera;g._camera_update()
 await touch(point,true);await touch(point,false,true)
 check("canceled touch does not locate",g.camera_focus==old_camera and g.commands==commands)
 await touch(point,true);await touch(point+Vector2(50,0),true,false,1);await touch(point,false);await touch(point+Vector2(50,0),false,false,1)
 check("two finger gesture does not locate",g.camera_focus==old_camera and g.commands==commands)
 await touch(point,true);await touch(point,false)
 check("fresh sole touch locates without world order",g.camera_focus==target.position and g.commands==commands and g.selected==selected)
 g._start_build("house");g.toast_time=0
 var plot=g.pointer_world;var held=g.build_preview_held;var before_build_bank=g.economy.bank_milli(0).duplicate(true)
 g._locate_tutorial()
 check("locate preserves unpaid building preview",g.build_mode=="house" and g.pointer_world==plot and g.build_preview_held==held and g.commands==commands and g.economy.bank_milli(0)==before_build_bank)
 g._cancel_mode()
 var bank=g.economy.bank_milli(0).duplicate(true)
 g._submit("order",{"ids":[worker.id],"target":target.id,"position":target.position},0)
 for i in 1000:
  g._tick(g.Rules.TICK)
  if g.demo_tutorial.achieved.has("deposit"):break
 check("ordinary gather really begins",g.demo_tutorial.achieved.has("gather"))
 check("ordinary delivery earns completion only after bank",g.demo_tutorial.achieved.has("deposit") and (g.economy.bank_milli(0).food>bank.food or g.economy.bank_milli(0).wood>bank.wood))
 g.demo_tutorial.skip();var achieved=g.demo_tutorial.achieved.duplicate();shell._open_menu();shell._show_page("help")
 shell.buttons.get_node("GuidedPracticeButton").pressed.emit()
 check("new guided match requires existing save warning",shell.page=="tutorial_confirm" and shell.description.text.contains("未儲存"))
 shell.buttons.get_node("CancelNewMatchButton").pressed.emit()
 check("cancel keeps same match and achievements",shell.match_node==g and g.demo_tutorial.achieved==achieved)
 shell._show_page("help");shell.buttons.get_node("ResumeTutorialButton").pressed.emit();shell.buttons.get_node("ResumeTutorialButton").pressed.emit()
 check("resume repeated preserves game and progress",shell.match_node==g and not g.demo_tutorial.skipped and g.demo_tutorial.achieved==achieved and g.paused)
 var snapshot=Codec.capture(g);check("tutorial progress still valid strict checkpoint",Codec.validate(snapshot))
 g.demo_tutorial.skip();Restore.apply(g,snapshot)
 check("strict restore preserves resumed progress",not g.demo_tutorial.skipped and g.demo_tutorial.achieved==achieved)
 shell._resume_match();await process_frame;g.set_process(false);g.toast_time=0;g._toggle_context_details("guidance")
 if g.context_detail_kind!="guidance":g._toggle_context_details("guidance")
 for size in [Vector2i(390,844),Vector2i(640,360),Vector2i(320,568)]:
  root.size=size;g._layout_ui();await process_frame;await process_frame
  check("guide controls fit "+str(size),Rect2(Vector2.ZERO,Vector2(size)).encloses(g.tutorial_locate.get_global_rect()) and g.tutorial_locate.size.y>=44)
 shell._open_menu()
 for size in [Vector2i(390,844),Vector2i(640,360),Vector2i(320,568)]:
  root.size=size;shell._show_page("help");await process_frame;await process_frame
  var fit=true
  for button in shell.buttons.get_children():fit=fit and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()) and button.size.y>=44
  check("help actions fit "+str(size),fit and shell.scroll.size.y>=50)
 # Explicit funded fixture for the unique irreversible research completion.
 # Ordinary production ticks, not a direct tutorial fact or age assignment.
 var research=load("res://main.tscn").instantiate();root.add_child(research);research.set_process(false);research.test_mode=true;research.ai_enabled=false
 var stock={"food":2000,"wood":3000,"stone":1000,"iron":1000}
 research._test_reset([stock,stock]);research.set_process(false)
 research.demo_tutorial.record("select");research.demo_tutorial.skip()
 var keep=research._first(0,"town_center")
 check("skipped research uses ordinary paid queue",research._enqueue_research(keep.id,0))
 research._resume_tutorial()
 check("pending research not credited by resume",not research.demo_tutorial.achieved.has("age2"))
 research.demo_tutorial.skip()
 for i in 1800:
  research.tick_count+=1
  for entity in research.entities:
   if entity.alive and entity.category=="building":research._update_production(entity,research.Rules.TICK,false)
  research._process_ready_production()
 check("skip still does not accumulate completed event",research.age_completed_tick[0]>=0 and not research.demo_tutorial.achieved.has("age2"))
 research._resume_tutorial();research._resume_tutorial()
 check("resume recovers only irreversible own age fact",research.demo_tutorial.achieved=={"select":true,"age2":true} and not research.demo_tutorial.skipped)
 var resumed=Codec.capture(research)
 check("recovered research validates and restores",Codec.validate(resumed) and Restore.apply(research,resumed) and research.demo_tutorial.achieved=={"select":true,"age2":true})
 check("resume grants no research refund or resource bonus",research.economy.audit().ok and research.economy.bank_milli(0).food<stock.food*1000)
 research.queue_free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"guided_tutorial_contract","checks":checks,"failed":failed,"scope":"Native menu and actual ordinary gather/delivery; value-only fog policy and camera invariants. Not physical phone or browser visual acceptance."}))
 quit(1 if failed else 0)
