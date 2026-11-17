extends "res://tests/contextual_touch_phone.gd"
func arrange(building,unit):
 game.camera_focus=building.pos;game._camera_update()
 var center=game.camera.unproject_position(building.pos+Vector3(0,1,0))
 var shift=game.camera.unproject_position(Vector3(0,.6,0))-game.camera.unproject_position(Vector3.ZERO)
 unit.pos=game._world_at(center+Vector2(25,0)-shift)
 game._update_vision(false);game._publish_faction_views()
 return center
func run():
 root.size=Vector2i(390,844)
 game=load("res://main.tscn").instantiate();root.add_child(game);game.set_process(false);game.test_mode=true;game._test_reset();game.set_process(false);await settle()
 var building=game._first(0,"town_center");var worker=game._first(0,"villager")
 for size in [Vector2i(390,844),Vector2i(844,390),Vector2i(320,568)]:
  root.size=size;game._layout_ui();await settle()
  for zoom in [15.0,30.0,46.0]:
   game.camera_zoom=zoom;var center=arrange(building,worker);var p=center+Vector2(15,0)
   game._select([]);game.commands.clear();await settle()
   check("world projection usable %s z%s" % [size,zoom],game._box_point_in_world(p) and game._pick(p)==building.id and game.camera.unproject_position(worker.pos+Vector3(0,.6,0)).distance_to(p)<10.01)
   await tap(p)
   check("routed closer worker selected %s z%s" % [size,zoom],game.selected==[worker.id] and game.commands.is_empty())
   await tap(center)
   check("routed building center retains priority %s z%s" % [size,zoom],game.selected==[building.id] and game.commands.is_empty())
 root.size=Vector2i(390,844);game._layout_ui();game.camera_zoom=30;await settle()
 var center=arrange(building,worker);var p=center+Vector2(15,0)
 var second=game._spawn("villager",0,worker.pos);game._update_vision(false);game._publish_faction_views()
 check("identical unit centers resolve stable lower id",game._friendly_unit_pick(p,building.id)==mini(worker.id,second.id))
 var observed=game.faction_views[0].current
 var modified=observed.duplicate(true);modified[worker.id].remembered=true;modified[second.id].alive=false
 game.faction_views[0].current=modified
 check("remembered and dead unit observations cannot steal selection",game._friendly_unit_pick(p,building.id)==building.id)
 modified.erase(worker.id);modified.erase(second.id);game.faction_views[0].current=modified
 check("absent units never queried through authority for selection",game._friendly_unit_pick(p,building.id)==building.id)
 game.faction_views[0].current=observed
 var enemy=game._spawn("spearman",1,Vector3(40,0,-40));game._update_vision(false);game._publish_faction_views()
 check("unseen actual enemy has no pick record",game.faction_views[0].get_record(enemy.id).is_empty() and game._friendly_unit_pick(p,building.id)==worker.id)
 var farm=game._spawn("farm",0,Vector3(-25,0,8));center=arrange(farm,worker);p=center+Vector2(15,0)
 # Keep the extra controlled worker outside the projected overlap.
 second.pos=Vector3(-14,0,14);game._update_vision(false);game._publish_faction_views()
 game._select([worker.id]);game.commands.clear();await settle()
 check("farm precondition legacy winner with closer worker",game._pick(p)==farm.id and game._friendly_unit_pick(p,farm.id)==farm.id)
 await tap(p)
 check("selected villager farm tap remains gather command",game.commands.size()==1 and game.commands[0].target==farm.id and game.commands[0].get("farm_gather",false) and game.selected==[worker.id])
 game.commands.clear();game.paused=true;game._select([worker.id]);await settle();await tap(p)
 check("paused farm tap selects nearer worker without gather",game.selected==[worker.id] and game.commands.is_empty())
 game.paused=false;farm.built=false;game._publish_faction_views();game._select([worker.id]);await settle();await tap(p)
 check("unfinished farm tap selects nearer worker without gather",game.selected==[worker.id] and game.commands.is_empty())
 farm.built=true;game._publish_faction_views()
 game.commands.clear();var army=game._spawn("spearman",0,Vector3(-23,0,12));game._update_vision(false);game._publish_faction_views();game._select([army.id]);await settle()
 await tap(center)
 check("selected army tapping friendly building center selects without order",game.selected==[farm.id] and game.commands.is_empty())
 var enemy_seen=game._spawn("spearman",1,farm.pos+Vector3(4,0,0));game._update_vision(false);game._publish_faction_views()
 check("visible enemy winner remains command-target eligible",game.faction_views[0].get_record(enemy_seen.id).get("alive",false) and game._friendly_unit_pick(p,enemy_seen.id)==enemy_seen.id)
 var resources=game.faction_views[0].records().values().filter(func(e):return e.category=="resource" and not e.remembered)
 check("visible resource mesh winner is not overridden",not resources.is_empty() and game._friendly_unit_pick(p,resources[0].id)==resources[0].id)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"friendly_pick_routed_contract","checks":checks,"failed":failed,"scope":"Actual viewport touch routing and camera at three sizes/zooms; controlled positions and explicit observation-filter fixtures; not physical phone or natural combat."}));quit(1 if failed else 0)
