extends SceneTree
# PREPARED ONLY. Synthetic controls, not parsing/runtime/phone evidence.
class Fixture:
	extends "res://scripts/game.gd"
	func _update_hud(): pass
	func _world_at(_screen): return Vector3.ZERO
	func _pick(_screen,_allow_enemy=true): return -1
var checks=0
var failures=0
func check(label,ok):
	checks+=1
	if not ok: failures+=1; push_error(label)
func _initialize():
	var g=Fixture.new()
	var valid={"id":1,"owned":true,"alive":true,"team":0,"category":"unit","remembered":false}
	g.faction_views[0].current={1:valid}
	g.selected=[1,999]
	g.commands=[{"team":0,"type":"stop","ids":[1]}]
	var queued=g.commands.duplicate(true)
	for mode in ["build","box","rally","ordinary"]:
		g.build_mode="house" if mode=="build" else ""
		g.build_preview_held=mode=="build"; g.box_select_mode=mode=="box"
		g.rally_building=8 if mode=="rally" else -1; g.touch_command=mode in ["rally","ordinary"]
		g.ghost=Node3D.new(); var old_ghost=g.ghost
		g.all_touch_ids=[4]; g.touch_points={4:Vector2(100,100)}; g.touch_press_epochs={4:3}
		g.pressed_mouse_buttons={MOUSE_BUTTON_LEFT:true}; g.dragging=true; g.drag_active=true
		g._start_unit_command()
		check(mode+" becomes only ordinary targeting",g.touch_command and g.build_mode.is_empty() and not g.build_preview_held and not g.box_select_mode and g.rally_building==-1)
		check(mode+" retires ghost and held pointers",g.ghost==null and old_ghost.is_queued_for_deletion() and g.canceled_touch_ids.has(4) and g.canceled_mouse_buttons.has(MOUSE_BUTTON_LEFT) and g.touch_points.is_empty() and g.touch_press_epochs.is_empty() and not g.dragging and not g.drag_active)
		check(mode+" preserves queue and selection",g.commands==queued and g.selected==[1,999])
		g._toggle_unit_command()
		check(mode+" toggles off without order",not g.touch_command and g.commands==queued and g.selected==[1,999])
	var building=valid.duplicate(); building.category="building"; building.id=2
	g.faction_views[0].current={1:valid,2:building}; g.selected=[2,1]
	g._start_unit_command()
	check("mixed building and unit selection retained",g.touch_command and g.selected==[2,1] and g.commands==queued)
	g._cancel_mode(); g.selected=[1,999]
	# Every rejection is evaluated against the current record, not cached eligibility.
	for invalid in [{},{"alive":false},{"owned":false},{"team":1},{"category":"building"},{"remembered":true}]:
		var record=valid.duplicate()
		if invalid.is_empty(): record={}
		else: record.merge(invalid,true)
		g.faction_views[0].current={1:record}
		for mode in ["build","rally","box"]:
			g.build_mode="house" if mode=="build" else ""; g.build_preview_held=mode=="build"
			g.rally_building=8 if mode=="rally" else -1; g.touch_command=mode=="rally"
			g.box_select_mode=mode=="box"; g.touch_box_index=5 if mode=="box" else -1
			g.touch_box_active=mode=="box"
			g.ghost=Node3D.new(); var ghost=g.ghost
			g.all_touch_ids=[5]; g.touch_points={5:Vector2.ONE}
			g._start_unit_command()
			check("reject "+str(invalid)+mode,g.build_mode==("house" if mode=="build" else "") and g.rally_building==(8 if mode=="rally" else -1) and g.touch_command==(mode=="rally") and g.ghost==ghost and not ghost.is_queued_for_deletion() and g.all_touch_ids==[5] and g.commands==queued and g.selected==[1,999])
			check("reject preserves box state "+str(invalid)+mode,g.box_select_mode==(mode=="box") and g.touch_box_index==(5 if mode=="box" else -1) and g.touch_box_active==(mode=="box") and g.touch_points=={5:Vector2.ONE})
			ghost.free(); g.ghost=null
	g._clear_box_select()
	g.faction_views[0].current={1:valid}; g.selected=[]; g.build_mode="house"; g.touch_command=false
	g._toggle_unit_command()
	check("empty selection preserves preview",not g.touch_command and g.build_mode=="house" and g.commands==queued)
	g.selected=[1]
	for flag in ["paused","game_over"]:
		g.set(flag,true); g._start_unit_command()
		check(flag+" rejects entry",not g.touch_command and g.build_mode=="house" and g.commands==queued)
		g.touch_command=true; g._toggle_unit_command()
		check(flag+" still allows cancellation",not g.touch_command and g.build_mode.is_empty() and g.commands==queued)
		g.set(flag,false); g.build_mode="house"
	g.order_marker=Node3D.new(); g._start_unit_command(); g._tap(Vector2.ZERO,true)
	check("build preview to command submits ordinary order",g.commands.size()==queued.size()+1 and g.commands[-1].type=="order" and g.commands[-1].ids==[1] and g.build_mode.is_empty() and not g.touch_command)
	g.order_marker.free(); g.free()
	print("COMMAND_MODE_ENTRY_CONTRACT %d/%d PREPARED synthetic control" % [checks-failures,checks])
	quit(1 if failures else 0)
