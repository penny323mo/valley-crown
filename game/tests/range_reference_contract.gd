extends SceneTree
const Overlay=preload("res://scripts/range_reference_overlay.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func settle():await process_frame;await process_frame
func run():
 var visible=PackedByteArray();visible.resize(Rules.MAP_SIZE*Rules.MAP_SIZE);visible.fill(1)
 var own={"id":1,"owned":true,"alive":true,"team":0,"remembered":false,"kind":"archer","built":true,"pos":Vector3.ZERO}
 var profile=Overlay.observed_profile({1:own},[1])
 check("single own archer uses authoritative base range",profile.radius==Rules.RANGE.archer)
 check("unselected and multi selected produce no circle",Overlay.observed_profile({1:own},[]).is_empty() and Overlay.observed_profile({1:own},[1,2]).is_empty())
 for field in ["owned","alive","team","remembered","built","kind"]:
  var wrong=own.duplicate();wrong[field]={"owned":false,"alive":false,"team":1,"remembered":true,"built":false,"kind":"spearman"}[field]
  check("reject noneligible "+field,Overlay.observed_profile({1:wrong},[1]).is_empty())
 var segments=Overlay.visible_segments(profile,visible)
 check("circle fixed 64 segments with exact ground radius",segments.size()==64 and segments.all(func(s):return absf(Vector2(s[0].x,s[0].z).length()-Rules.RANGE.archer)<.001))
 var hidden=visible.duplicate();hidden.fill(0)
 check("hidden or invalid visibility produces no circle",Overlay.visible_segments(profile,hidden).is_empty() and Overlay.visible_segments(profile,[]).is_empty())
 # Only one half is visible. Each emitted segment must stay in visible x<0 cells.
 for y in Rules.MAP_SIZE:
  for x in range(Rules.MAP_SIZE/2,Rules.MAP_SIZE):visible[y*Rules.MAP_SIZE+x]=0
 profile.position=Vector3(-.1,0,0)
 segments=Overlay.visible_segments(profile,visible)
 check("fog clips outline rather than drawing through remembered area",segments.size()>0 and segments.size()<64 and segments.all(func(s):return s[0].x<0 and s[1].x<0))
 var shell=load("res://main_menu.tscn").instantiate();root.add_child(shell);await settle()
 shell._choose_battle("standard");shell._start_match();await settle()
 var g=shell.match_node
 if not is_instance_valid(g) or not is_instance_valid(g.camera):push_error("game initialization failed");quit(2);return
 g.set_process(false);g.ai_enabled=false
 var archer=g._spawn("archer",0,g._first(0,"villager").pos+Vector3(2,0,2));g._update_vision();g._select([archer.id]);g._update_hud()
 var o=g.ui.get_node("RangeReferenceOverlay")
 check("native owned selection enables circle and touch readable detail",not o.profile().is_empty() and g.selection_detail.text.contains("至目標邊緣"))
 check("overlay never captures pointer input",o.mouse_filter==Control.MOUSE_FILTER_IGNORE)
 var before={"bank":g.economy.bank_milli(0).duplicate(true),"commands":g.commands.duplicate(true),"tick":g.tick_count,"selected":g.selected.duplicate(),"visible":g.visible_cells[0].duplicate(),"explored":g.explored_cells[0].duplicate(),"observed":g.faction_views[0].records().duplicate(true)}
 for size in [Vector2i(390,844),Vector2i(640,360),Vector2i(320,568)]:
  root.size=size;g._layout_ui();g._camera_update();await settle()
  check("overlay full viewport without input obstruction "+str(size),o.size==Vector2(size) and o.mouse_filter==Control.MOUSE_FILTER_IGNORE and not o.profile().is_empty())
 check("drawing changes no commands resources selection tick or fog",g.economy.bank_milli(0)==before.bank and g.commands==before.commands and g.tick_count==before.tick and g.selected==before.selected and g.visible_cells[0]==before.visible and g.explored_cells[0]==before.explored and g.faction_views[0].records()==before.observed)
 # Actual engine pointer dispatch reaches the world through the passive overlay.
 root.size=Vector2i(960,640);g._layout_ui();g._camera_update();await settle()
 var issued=false
 if g._box_point_in_world(g.camera.unproject_position(archer.pos+Vector3(3,0,0))):
  var p=g.camera.unproject_position(archer.pos+Vector3(3,0,0))
  for down in [true,false]:
   var e=InputEventMouseButton.new();e.position=p;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;root.push_input(e);await process_frame
  issued=g.commands.any(func(c):return c.get("type","")=="order" and c.get("target",-2)==-1 and archer.id in c.get("ids",[]))
 check("ordinary click dispatch passes overlay to movement command",issued)
 g.commands.clear();g._cancel_pointer_streams()
 var enemy=g._spawn("spearman",1,archer.pos+Vector3(Rules.RANGE.archer+.2,0,0));g._update_vision()
 check("reference radius is target edge not target centre",enemy.radius>.2 and g._attack_distance(archer.pos,enemy)<Rules.RANGE.archer)
 check("normal visible target beyond circle centre can still receive legal shot",g._release_attack(archer,enemy).get("applied",false))
 g.paused=true;check("pause hides overlay",o.profile().is_empty());g.paused=false
 g.application_focused=false;check("focus loss hides overlay",o.profile().is_empty());g.application_focused=true
 g.touch_command=true;check("command targeting hides selection circle",o.profile().is_empty());g.touch_command=false
 var tower=g._spawn("tower",0,archer.pos+Vector3(4,0,0));g._update_vision();g._select([tower.id])
 check("own completed tower uses tower range",o.profile().radius==Rules.RANGE.tower)
 g._select([g._first(0,"villager").id]);g._start_build("tower")
 # Controlled valid placement receipt: choose ordinary visible free site with real gate.
 var found=false
 for z in range(-12,13):
  for x in range(-12,13):
   if found:break
   g.pointer_world=g._first(0,"town_center").pos+Vector3(x,0,z);g._update_ghost()
   if g.placement_ok and Overlay.cell_visible(g.ghost.global_position,g.visible_cells[0]):found=true
 check("ordinary legal tower preview has circle",found and o.profile().get("preview",false))
 g.placement_ok=false;check("invalid tower placement has no misleading coverage",o.profile().is_empty())
 g._cancel_mode();check("cancel construction removes preview circle",o.profile().is_empty())
 g._select([archer.id]);g._submit("surrender",{},0);g._tick(Rules.TICK)
 check("settlement and inspection hide circle",g.game_over and o.profile().is_empty())
 g._set_aftermath_view(true);check("aftermath does not revive stale selection coverage",o.profile().is_empty())
 print(JSON.stringify({"suite":"range_reference_contract","checks":checks,"failed":checks.filter(func(c):return not c.passed).size(),"scope":"Native controlled units, read-only range geometry and ordinary placement gates; no rendered or physical phone claim."}))
 shell.queue_free();await settle();quit(1 if checks.any(func(c):return not c.passed) else 0)
