extends SceneTree
## Narrow event-routing fixtures. Actual input; controlled incidents/clock.
const Rules=preload("res://scripts/rules.gd")
const BattleAlerts=preload("res://scripts/battle_alerts.gd")
const CheckpointCodec=preload("res://scripts/checkpoint_codec.gd")
var checks=[]
var g

func _initialize():call_deferred("run")
func check(name,pass_state):
	checks.append({"name":name,"passed":bool(pass_state)})
	if not pass_state:push_error(name)
	return bool(pass_state)
func settle():
	for i in 4:await process_frame
func touch(p,pressed,index=61,canceled=false):
	var e=InputEventScreenTouch.new()
	e.position=p;e.index=index;e.pressed=pressed;e.canceled=canceled
	root.push_input(e);await settle()
func tap(b):
	if not fits(b):return false
	var p=b.get_global_rect().get_center()
	await touch(p,true);await touch(p,false)
	return true
func fits(b):
	if not is_instance_valid(b) or not b.is_visible_in_tree() or b.disabled:return false
	var r=b.get_global_rect()
	if r.size.x<44 or r.size.y<44 or not root.get_visible_rect().encloses(r):return false
	var parent=b.get_parent()
	while parent is Control:
		if parent.clip_contents and not parent.get_global_rect().encloses(r):return false
		parent=parent.get_parent()
	return true
func refresh():
	g._update_hud()
	await settle()
func hit(p,team=0):
	var v={"team":team,"alive":true,"category":"building","kind":"town_center","pos":p}
	return g.battle_alerts.record_hit(v,1,g.tick_count)
func state():
	return [g.selected.duplicate(),g.commands.duplicate(true),g.command_sequence,g.economy.bank_milli(0),g.visible_cells[0].duplicate(),g.progress_serial]
func toolbar():
	return [g.hud_top.get_global_rect(),g.pause_button.get_global_rect(),g.compact_menu_button.get_global_rect(),g.inline_idle_worker_button.get_global_rect(),g.inline_idle_worker_button.visible,g.tutorial_entry.get_global_rect(),g.tutorial_entry.visible]
func reopen():
	return await tap(g.compact_menu_button) and g.compact_menu.visible
func fixture(size):
	root.size=size
	g=load("res://main.tscn").instantiate()
	root.add_child(g);g.set_process(false);g.test_mode=true;g.ai_enabled=false
	await refresh()

func exercise(size):
	await fixture(size)
	var id=str(size)+" "
	var b=g.battle_return_button
	var base=toolbar()
	var start=Vector3(-24,0,23)
	var another=Vector3(-5,0,5)
	var away=Vector3(6,0,3)
	var no_hit=state()
	check(id+"visual return unavailable before actual incident",not b.visible and not g.battle_jump_button.visible)
	check(id+"hostile-only position not tracked",not hit(another,1) and g.battle_alerts.acknowledged_site(g.tick_count).is_empty())
	check(id+"first friendly incident shows only stock unread priority",hit(start))
	await refresh()
	check(id+"first unread routed tap acknowledged, no order or new message",fits(g.battle_jump_button) and await tap(g.battle_jump_button) and g.camera_focus==start and not g.battle_jump_button.visible and g.battle_alerts.pending(g.tick_count).is_empty() and state()==no_hit)
	g.camera_focus=away;g._camera_update();await refresh()
	check(id+"after ack topbar geometry and normal idle position unchanged",toolbar()==base and g.camera_focus==away)
	check(id+"real Menu opens to reachable pinned return",await reopen() and fits(b) and not g.shortcut_scroll.is_ancestor_of(b) and b.text=="回看")
	check(id+"all category controls plus current title remain reachable",g.shortcut_category_buttons.values().all(func(q):return fits(q) and not q.get_global_rect().intersects(b.get_global_rect())))
	check(id+"return still pinned after routed Settings",await tap(g.shortcut_category_buttons.settings) and g.shortcut_category=="settings" and fits(b))
	var p=b.get_global_rect().get_center()
	await touch(p,true)
	var owned=g.gui_touch_press.has(61)
	g.tick_count+=100
	var previous=g.battle_alerts.acknowledged_site(g.tick_count).sequence
	check(id+"repeat at same point stays quiet",not hit(start) and g.battle_alerts.pending(g.tick_count).is_empty())
	await refresh()
	check(id+"same point does not invalidate held stable target",owned and g.gui_touch_press.has(61) and b.get_global_rect().get_center()==p and g.battle_alerts.acknowledged_site(g.tick_count).sequence==previous)
	await touch(p,false)
	check(id+"valid release returns camera only and closes drawer",g.camera_focus==start and not g.compact_menu.visible and g.shortcut_category=="settings" and state()==no_hit and g.battle_alerts.pending(g.tick_count).is_empty())
	g.camera_focus=away;g._camera_update()
	check(id+"repeat explicit camera-only action still possible",await reopen() and fits(b))
	p=b.get_global_rect().get_center()
	await touch(p,true);await touch(p,false,61,true)
	check(id+"cancelled routed contact cannot jump",g.camera_focus==away and g.compact_menu.visible and state()==no_hit)
	await touch(p,true)
	check(id+"new friendly point in same incident remains quiet",not hit(start+Vector3(1,0,0)) and g.battle_alerts.pending(g.tick_count).is_empty() and g.battle_alerts.acknowledged_site(g.tick_count).sequence==previous)
	await refresh()
	await touch(p,false)
	check(id+"held tap cannot redirect to a different settled point",g.camera_focus==away and g.compact_menu.visible and state()==no_hit)
	check(id+"a fresh touch takes new recent point with no orders",await tap(b) and g.camera_focus==start+Vector3(1,0,0) and not g.compact_menu.visible and state()==no_hit)
	g.camera_focus=away;g._camera_update()
	check(id+"reopen without action before new threat",await reopen() and g.camera_focus==away and fits(b))
	p=b.get_global_rect().get_center()
	await touch(p,true)
	check(id+"new distinct friendly area still creates unread",hit(another))
	await refresh()
	await touch(p,false)
	check(id+"new unread preempts held quiet action without playing new action",not b.visible and fits(g.battle_jump_button) and g.camera_focus==away and g.compact_menu.visible and g.battle_alerts.pending(g.tick_count).size()==1 and state()==no_hit)
	check(id+"ordinary unread Route handled separately",await tap(g.battle_jump_button) and g.camera_focus==another and not g.compact_menu.visible and g.battle_alerts.pending(g.tick_count).is_empty())
	g.camera_focus=away;g._camera_update();await refresh()
	check(id+"reopen newest acknowledged incident",await reopen() and fits(b) and g.battle_alerts.acknowledged_site(g.tick_count).position==another)
	var cam=g.camera
	g.camera=null
	g._refresh_attack_alert()
	b.pressed.emit()
	check(id+"missing camera fails closed with no navigation",b.disabled and g.camera_focus==away and g.compact_menu.visible and state()==no_hit)
	g.camera=cam
	await refresh()
	var pause_rect=g.pause_button.get_global_rect()
	p=b.get_global_rect().get_center()
	await touch(p,true)
	g._toggle_pause();await refresh();await touch(p,false)
	check(id+"pause retires held target and preserves quiet time and geometry",b.visible and b.disabled and g.paused and g.pause_button.get_global_rect()==pause_rect and g.battle_alerts.acknowledged_site(g.tick_count).position==another and g.camera_focus==away)
	g._toggle_pause();await refresh()
	p=b.get_global_rect().get_center()
	await touch(p,true)
	root.size=size+Vector2i(24,18)
	await settle();await touch(p,false)
	check(id+"real viewport resize retires held touch without command",g.camera_focus==away and state()==no_hit)
	root.size=size;await settle();await refresh()
	g.build_mode="house";g.build_preview_held=true
	await refresh()
	b.pressed.emit()
	check(id+"active draft cannot be canceled or moved by return",b.visible and b.disabled and g.camera_focus==away and g.build_mode=="house" and g.build_preview_held and state()==no_hit)
	g._cancel_mode();await refresh()
	p=b.get_global_rect().get_center()
	await touch(p,true)
	g.tick_count+=100;hit(start+Vector3(1,0,0))
	await refresh()
	g.tick_count+=140;await refresh();await touch(p,false)
	check(id+"falling back to another still-live acknowledged area retires held touch",fits(b) and g.battle_alerts.acknowledged_site(g.tick_count).position==start+Vector3(1,0,0) and g.camera_focus==away and state()==no_hit)
	p=b.get_global_rect().get_center()
	await touch(p,true)
	g.tick_count+=100;await refresh();await touch(p,false)
	check(id+"expired held action and post-silence position cannot navigate",not fits(b) and not b.visible and g.camera_focus==away and state()==no_hit)
	check(id+"only a genuinely new hit after quiet expiry becomes unread",hit(start) and g.battle_alerts.pending(g.tick_count).size()==1)
	await refresh()
	check(id+"unread visible while terminal does not inherit quiet return",await tap(g.battle_jump_button))
	g.game_over=true;await refresh()
	check(id+"game end removes both actions",not b.visible and not g.battle_jump_button.visible and not g.compact_menu.visible)
	g.free();g=null;await settle()

func test_checkpoint_and_bounds():
	var a=BattleAlerts.new()
	var p=Vector3(-15,0,12)
	var record={"team":0,"alive":true,"category":"unit","kind":"scout","pos":p}
	a.record_hit(record,1,1)
	var original=a.acknowledge(1,1)
	record.pos+=Vector3(3,0,0)
	a.record_hit(record,1,2)
	var frozen=CheckpointCodec.copy_fields(a,CheckpointCodec.MODULE_FIELDS.battle_alerts).duplicate(true)
	check("checkpoint record shape and original frozen alert identity remain unchanged",frozen.size()==2 and frozen.has("serial") and frozen.has("entries") and frozen.entries.size()==1 and frozen.entries[0].size()==5 and frozen.entries[0].position==original.position and a.acknowledged_site(2).position==record.pos)
	var restored=BattleAlerts.new()
	restored.entries=frozen.entries;restored.serial=frozen.serial
	check("existing save restores last frozen friendly point, not transient latest",restored.acknowledged_site(2).position==p and restored.pending(2).is_empty())
	restored.entries[0].position=Vector3.INF
	check("nonfinite restore presentation fails closed",restored.acknowledged_site(2).is_empty())
	for i in 5:
		record.pos=Vector3(i*8,0,14)
		a.record_hit(record,1,2+i)
		a.record_hit(record,1,2+i)
	check("transient location cache eviction tracks only retained sequences",a.entries.size()==4 and a._recent_friendly_positions.size()==4 and not a._recent_friendly_positions.has(1))
	a.acknowledged_site(246)
	check("expiry clears all transient coordinates",a._recent_friendly_positions.is_empty() and a.entries.is_empty())
	a.record_hit(record,1,247);a.record_hit(record,1,247);a.reset()
	check("reset also retires transient coordinates without serial reuse",a._recent_friendly_positions.is_empty() and a.entries.is_empty() and a.serial>4)

func run():
	test_checkpoint_and_bounds()
	await exercise(Vector2i(480,270))
	await exercise(Vector2i(568,320))
	await exercise(Vector2i(320,568))
	var failed=checks.filter(func(x):return not x.passed).size()
	print(JSON.stringify({"suite":"battle_return_quiet_contract","build":Rules.BUILD_ID,"checks":checks,"failed":failed,"scope":"Controlled settled-friendly record/clock fixture and actual viewport-routed screen touches; not a natural match or rendered/physical phone evidence."}))
	quit(1 if failed else 0)
