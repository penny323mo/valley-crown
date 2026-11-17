extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
var g
var m
var checks=[]
func check(n,b):checks.append({"name":n,"passed":bool(b)})
func _initialize():call_deferred("run")
func touch(id,p,down,canceled=false):
 var e=InputEventScreenTouch.new();e.index=id;e.position=p;e.pressed=down;e.canceled=canceled
 root.push_input(e);await process_frame
func drag(id,p):
 var e=InputEventScreenDrag.new();e.index=id;e.position=p;e.relative=Vector2(20,10)
 root.push_input(e);await process_frame
func mouse(p,down):
 var e=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.position=p;e.pressed=down
 root.push_input(e);await process_frame
func motion(p,held=true):
 var e=InputEventMouseMotion.new();e.position=p;e.relative=Vector2(20,10);e.button_mask=MOUSE_BUTTON_MASK_LEFT if held else 0
 root.push_input(e);await process_frame
func run():
 root.size=Vector2i(960,540)
 g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g._test_reset();g.set_process(false)
 g.compact_map_choice=1;g.tutorial_panel.hide();g._layout_ui()
 await process_frame;await process_frame
 m=g.minimap
 check("minimap visible in actual UI",m.is_visible_in_tree() and m.size.x==124)
 var worker=g._first(0,"villager");g._select([worker.id]);g._start_build("house")
 var selected=g.selected.duplicate();var original_commands=g.commands.duplicate(true);var mode=g.build_mode
 var p=m.global_position+Vector2(35,35);var q=m.global_position+Vector2(85,70)
 await touch(2,p,true);var first=g.camera_focus
 await drag(2,q)
 check("routed sole finger continuously pans minimap",g.camera_focus!=first and not m.pointer.is_empty())
 check("minimap drag preserves selection build mode and commands",g.selected==selected and g.build_mode==mode and g.commands==original_commands)
 await touch(2,q,false)
 check("routed release ends map ownership",m.pointer.is_empty())
 await touch(2,p,true);var before=g.camera_focus
 await drag(2,m.global_position+Vector2(200,60));await drag(2,q)
 check("outside crossing quarantines until release",g.camera_focus==before)
 await touch(2,Vector2(500,270),false)
 check("outside release never issues world command",g.commands==original_commands and g.selected==selected)
 await touch(2,p,true);before=g.camera_focus
 await touch(3,q,true);await drag(2,q);await touch(3,q,false);await drag(2,q)
 check("second finger and remaining finger cannot pan map",g.camera_focus==before)
 await touch(2,q,false)
 await touch(2,p,true);before=g.camera_focus
 await touch(2,q,false,true);await drag(2,q)
 check("cancelled touch cannot revive drag",g.camera_focus==before and m.pointer.is_empty())
 await touch(2,p,true);before=g.camera_focus;m.hide();await drag(2,q);await touch(2,q,false)
 check("hidden minimap cancels live drag",g.camera_focus==before and m.pointer.is_empty())
 m.show();await touch(2,p,true);before=g.camera_focus;g._cancel_pointer_streams();await drag(2,q);await touch(2,q,false)
 check("global pointer cancellation clears map stream",g.camera_focus==before and m.pointer.is_empty())
 await mouse(p,true);first=g.camera_focus;await motion(q)
 check("routed left mouse drag pans",g.camera_focus!=first)
 await mouse(q,false);before=g.camera_focus;await motion(p,false)
 check("released mouse cannot continue minimap movement",g.camera_focus==before and m.pointer.is_empty())
 await mouse(p,true);before=g.camera_focus;m.hide();m.show();await motion(q)
 check("hide show without input never revives mouse stream",g.camera_focus==before)
 await mouse(q,true);await motion(q)
 check("duplicate press cannot restart quarantined mouse stream",g.camera_focus==before)
 await mouse(q,false)
 await touch(2,p,true);before=g.camera_focus;m.hide();m.show();await drag(2,q)
 check("hide show without input never revives touch stream",g.camera_focus==before)
 await touch(2,q,false)
 await touch(2,p,true);before=g.camera_focus;g._toggle_pause();g._toggle_pause();await drag(2,q);await touch(2,q,false)
 check("pause resume cancels held minimap stream",g.camera_focus==before and m.pointer.is_empty())
 check("all routed map streams preserve troop orders",g.commands==original_commands and g.selected==selected)
 # Isolated fog pixels, not gameplay screenshots. No enemy authority queried.
 g.visible_cells[0].fill(0);g.explored_cells[0].fill(0)
 g.explored_cells[0][81]=1;g.visible_cells[0][82]=1;m.refresh_fog()
 check("unknown explored visible pixels differ correctly",m.fog_image.get_pixel(0,0).is_equal_approx(m.UNSEEN) and m.fog_image.get_pixel(1,1).is_equal_approx(m.EXPLORED) and m.fog_image.get_pixel(2,1).is_equal_approx(m.VISIBLE))
 var texture=m.fog_texture;var updates=m.fog_updates;m.refresh_fog()
 check("unchanged fog uses cached texture without upload",m.fog_updates==updates and m.fog_texture==texture)
 g.visible_cells[1].fill(1);g.explored_cells[1].fill(1);m.refresh_fog()
 check("opponent fog cannot reveal minimap",m.fog_updates==updates and m.fog_image.get_pixel(0,0).is_equal_approx(m.UNSEEN))
 g.visible_cells[0][82]=0;g.explored_cells[0][82]=1;m.refresh_fog()
 check("lost sight becomes explored not current",m.fog_updates==updates+1 and m.fog_image.get_pixel(2,1).is_equal_approx(m.EXPLORED) and m.fog_texture==texture)
 g.explored_cells[0].fill(0);m.refresh_fog()
 check("same tick reset clears cached explored region",m.fog_image.get_pixel(1,1).is_equal_approx(m.UNSEEN))
 # Exact checkpoint restore must publish restored fog before any next frame.
 g._test_reset();g.set_process(false);g.explored_cells[0][81]=1
 var saved=Codec.capture(g)
 check("fog checkpoint valid",Codec.validate(saved))
 g.explored_cells[0][81]=0;m.refresh_fog()
 var tick=saved.game.tick_count
 check("checkpoint restoration succeeds",Restore.apply(g,saved))
 check("restored minimap fog immediate without frame or tick",g.tick_count==tick and g.paused and m.fog_image.get_pixel(1,1).is_equal_approx(m.EXPLORED))
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"minimap_navigation_contract","checks":checks,"failed":failed,"scope":"Native viewport push_input GUI routing with actual HUD, plus isolated player fog pixel/cache tests. Not browser or physical phone."}))
 quit(1 if failed else 0)
