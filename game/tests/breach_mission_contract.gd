extends SceneTree
const Rules=preload("res://scripts/rules.gd")
const Mission=preload("res://scripts/breach_mission.gd")
const Store=preload("res://scripts/checkpoint_store.gd")
const Auto=preload("res://scripts/auto_checkpoint.gd")
const Catalogue=preload("res://scripts/battle_selection.gd")
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func run():
 root.size=Vector2i(960,640)
 var m=Mission.new()
 check("live front blocks stage",not m.advance(1,true,false) and m.stage==0)
 check("front death advances once",m.advance(2,false,true) and m.stage==1 and m.stage_ticks==[2])
 check("keep death finishes second objective",m.advance(3,false,false) and m.stage==2)
 check("complete cannot repeat",not m.advance(4,false,false) and m.stage_ticks==[2,3])
 var simultaneous=Mission.new()
 check("both objective deaths close in same tick",simultaneous.advance(5,false,false) and simultaneous.stage==2 and simultaneous.stage_ticks==[5,5])
 var early_keep=Mission.new();early_keep.advance(1,true,false)
 check("early keep death waits then closes with front death",early_keep.stage==0 and early_keep.advance(7,false,false) and early_keep.stage==2 and early_keep.stage_ticks==[7,7])
 check("catalogue has disclosed mission entry",Catalogue.option("breach").mode=="breach" and Catalogue.briefing("breach","conquest").contains("暫不支援存檔"))
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="breach";g.history_path="/tmp/v97-contract-history.json";root.add_child(g);g.set_process(false);g.test_mode=true
 await process_frame;await process_frame
 check("mission selected without standard fallback",g.skirmish_mode=="breach")
 var army=g.entities.filter(func(e):return e.team==0 and e.category=="unit" and e.kind!="villager" and e.kind!="scout")
 check("twelve authored army with two siege",army.size()==12 and army.filter(func(e):return e.kind=="siege").size()==2)
 check("all starting troops clear static navigation geometry",army.all(func(e):return g._static_unit_step_is_free(e,e.pos)))
 check("all starting troops clear other unit bodies",army.all(func(e):return g._unit_step_is_free(e,e.pos)))
 check("standard opening bank not inflated",g.economy.bank_milli(0).wood==200000 and g.economy.bank_milli(0).stone==100000)
 var walls=g.entities.filter(func(e):return e.kind=="wall")
 check("sixteen real blocking wall entities",walls.size()==16 and walls.all(func(e):return e.team==1 and e.built and e.hp==250))
 var fort_clear=true
 for fort in walls+[g._get_entity(g.breach_mission.post_id)]:
  var cells=g._occupied_cells(fort)
  for other in g.entities:
   if other.id==fort.id or other.category=="unit":continue
   for cell in g._occupied_cells(other):
    if cell in cells:fort_clear=false;print("FORT_OVERLAP ",fort.id," ",fort.pos," with ",other.id," ",other.kind," ",other.pos)
 check("authored fort footprints do not overlap static world",fort_clear)
 check("all fixed defenders clear static geometry",g.entities.filter(func(e):return e.team==1 and e.category=="unit").all(func(e):return g._static_unit_step_is_free(e,e.pos)))
 check("enemy has fixed four defenders no workers",g.entities.filter(func(e):return e.team==1 and e.category=="unit").size()==4 and g._first(1,"villager").is_empty())
 check("built military production supports paid replacements",not g._first(0,"workshop").is_empty() and g._age2(0))
 var visible=g.visible_cells.duplicate(true);var explored=g.explored_cells.duplicate(true);var commands=g.commands.duplicate(true);var selection=g.selected.duplicate()
 g._focus_control_point()
 check("objective focus changes only camera",g.camera_focus==Mission.FRONT and g.visible_cells==visible and g.explored_cells==explored and g.commands==commands and g.selected==selection)
 check("objective position does not reveal front tower",not g.faction_views[0].get_record(g.breach_mission.post_id).get("alive",false))
 check("manual save refuses without writing",not Store.save_slot(g,"/tmp/v97-never-save.bin").ok and not FileAccess.file_exists("/tmp/v97-never-save.bin"))
 check("automatic save unsupported",not Auto.supported(g))
 for i in 40:g._tick(Rules.TICK)
 check("scenario economic AI never starts",g.ai_enabled and g.ai_raids==0 and g._first(1,"villager").is_empty())
 for size in [Vector2i(390,844),Vector2i(640,360),Vector2i(320,568)]:
  root.size=size;g._layout_ui();await process_frame;await process_frame;g._refresh_control_point_marker()
  check("objective visible "+str(size),g.objective_button.is_visible_in_tree() and g.objective_button.text.contains("攻破前哨") and Rect2(Vector2.ZERO,Vector2(size)).encloses(g.objective_button.get_global_rect()))
 g._submit("surrender",{},0);g._tick(Rules.TICK)
 check("ordinary surrender defeats mission",g.game_over and g.outcome=="defeat")
 g.free();await process_frame
 print(JSON.stringify({"suite":"breach_mission_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"Native scenario seed/objective/fog/save refusal/viewport and surrender; combat completion tested separately with ordinary commands."}))
 quit(1 if checks.any(func(c):return not c.passed) else 0)
