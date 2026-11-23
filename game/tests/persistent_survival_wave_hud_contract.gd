extends SceneTree
## Focused native render-tree and routed inputs over controlled public phase
## states. The natural uninterrupted three-wave journey lives separately.
const Director=preload("res://scripts/siege_challenge.gd")
const Rules=preload("res://scripts/rules.gd")
var checks=[]
var evidence={}
var g=null

func _initialize():call_deferred("run")
func ck(name,value):
	checks.append({"name":name,"passed":bool(value)})
	if not value:push_error(name)
func frames():
	for i in 5:await process_frame
func shape(node):
	var r=node.get_global_rect()
	return [r.position.x,r.position.y,r.size.x,r.size.y]
func fits(node):
	if not node.is_visible_in_tree():return false
	var r=node.get_global_rect()
	return root.get_visible_rect().encloses(r) and g.hud_top.get_global_rect().encloses(r)
func lexically_fits(node):
	var f=node.get_theme_font("font")
	for c in node.text:
		if c!="\n" and not f.has_char(c.unicode_at(0)):return false
	return f.get_string_size(node.text,HORIZONTAL_ALIGNMENT_LEFT,-1,node.get_theme_font_size("font_size")).x<=node.size.x
func touch(idx,p,down):
	var ev=InputEventScreenTouch.new()
	ev.index=idx;ev.pressed=down;ev.position=p;root.push_input(ev)
func tap(node):
	var p=node.get_global_rect().get_center()
	touch(0,p,true);await process_frame;touch(0,p,false);await frames()
func settle():
	g._update_hud();g._layout_ui();await frames()
func resize(v):
	root.size=v;await frames();await settle()
func close_training_toast():
	# Wait presentation frames through the live _process route, not redefining
	# the natural director (the separate journey uses ordinary elapsed ticks).
	while g.toast_time>0 and g.paused:g._process(0.05)
	await settle()
func snapshot():
	var label=g.survival_wave_status
	var buttons={}
	for button in [g.pause_button,g.compact_menu_button,g.battle_jump_button]:
		if button.visible:buttons[button.text]=shape(button)
	return {"status":shape(label),"status_text":label.text,"font":label.get_theme_font_size("font_size"),"hud":shape(g.hud_top),"clock":shape(g.time_label),"time":g.time_label.text,"buttons":buttons,"resource":shape(g.top_resources)}
func assert_current_contract(name,expected_height):
	var wave=g.survival_wave_status
	var no_overlap=true
	for other in [g.time_label,g.top_resources,g.pause_button,g.compact_menu_button,g.battle_jump_button]:
		if other.is_visible_in_tree():no_overlap=no_overlap and not wave.get_global_rect().intersects(other.get_global_rect())
	ck(name+" persistent text fits at 13 px with bundled glyphs",fits(wave) and wave.get_theme_font_size("font_size")==13 and lexically_fits(wave))
	ck(name+" same top HUD world boundary, separate real clock and non-overlap",g.hud_top.size.y==expected_height and fits(g.time_label) and lexically_fits(g.time_label) and no_overlap)
	var reachable=true
	for button in [g.pause_button,g.compact_menu_button,g.battle_jump_button]:
		if button.visible:reachable=reachable and fits(button) and button.size.x>=44 and button.size.y>=44
	ck(name+" all enabled native controls retain whole ≥44px geometry",reachable)
	ck(name+" status and column do not take pointer",wave.mouse_filter==Control.MOUSE_FILTER_IGNORE and wave.get_parent().mouse_filter==Control.MOUSE_FILTER_IGNORE and not g._box_point_in_world(wave.get_global_rect().get_center()))
	evidence[name]=snapshot()

func finish():
	var failed=checks.filter(func(x):return not x.passed).size()
	print(JSON.stringify({"suite":"persistent_survival_wave_hud_contract","checks":checks,"failed":failed,"evidence":evidence,"scope":"Native routed touches plus controlled times/alert; three-wave story verified separately, no physical iPhone or browser."}))
	if is_instance_valid(g):g.free()
	quit(1 if failed else 0)

func run():
	root.size=Vector2i(568,320)
	var director=Director.new()
	ck("opening digits are a live countdown, never claim a launch at zero",director.hud_caption(0)=="1/3 整備45秒" and director.hud_caption(20)=="1/3 整備44秒" and director.hud_caption(899)=="1/3 整備1秒" and director.hud_caption(900)=="1/3 待出發")
	ck("six ordinary slots authorize first active public wave",director.launch([1,2,3,4,5,6]) and director.hud_caption(900)=="1/3 迎擊")
	director.observe(1000,func(id):return id==6)
	ck("one survivor leaves first wave active, not a false new countdown",director.hud_caption(1800)=="1/3 迎擊")
	ck("earlier active drawer wording is exactly unchanged",director.caption(1800)=="守城挑戰：第 1 / 3 波 · 擊退本波後有 45 秒整備；保護主堡。")
	director.observe(1850,func(_id):return false)
	ck("ordinary clear shows full new count and waits at boundary",director.hud_caption(1850)=="2/3 整備45秒" and director.hud_caption(2750)=="2/3 待出發")
	director.launch([7,8,9,10,11,12,13,14]);director.observe(3600,func(_id):return false)
	ck("third preparation is distinct from ongoing last wave",director.hud_caption(3600)=="3/3 整備45秒")
	director.launch([15,16,17,18,19,20,21,22,23,24,25,26])
	ck("last wave cannot imply a fourth countdown while any fighter lives",director.hud_caption(4500)=="3/3 最後一波")
	director.observe(4700,func(_id):return false)
	ck("terminal state has no countdown or battle notice",director.hud_caption(4700).is_empty())
	g=load("res://main.tscn").instantiate()
	g.skirmish_mode="survival";root.add_child(g);g.set_process(false);g.test_mode=true
	await settle()
	ck("opening ordinary exact clock remains independent of countdown",g.survival_wave_status.text=="1/3 整備45秒" and g.time_label.text=="00:00")
	for p in [[Vector2i(320,568),104],[Vector2i(390,844),104],[Vector2i(568,320),54],[Vector2i(844,390),54],[Vector2i(1280,720),54]]:
		await resize(p[0]);assert_current_contract(str(p[0])+" prep",p[1])
	await resize(Vector2i(568,320))
	ck("568 preparation retains exact paid timer, pause and menu coordinates",g.time_label.get_global_rect()==Rect2(377,22,35,22) and g.pause_button.get_global_rect()==Rect2(422,10,60,46) and g.compact_menu_button.get_global_rect()==Rect2(492,10,60,46))
	var selection=g.selected.duplicate();var seq=g.command_sequence;var bank=g.economy.bank_milli(0);var camera=g.camera_focus
	await tap(g.survival_wave_status)
	ck("touch over paint-only status never becomes world command, menu or mode",g.selected==selection and g.command_sequence==seq and g.economy.bank_milli(0)==bank and g.camera_focus==camera and not g.compact_menu.visible and not g.paused)
	await tap(g.pause_button)
	var initial=g.survival_wave_status.text
	g._process(0.75)
	await settle()
	ck("ordinary Pause action freezes actual match clock and wave status",g.paused and g.survival_wave_status.text==initial and g.time_label.text=="00:00" and g.command_sequence==seq)
	await close_training_toast()
	await tap(g.pause_button)
	ck("ordinary Resume action still works",not g.paused)
	# Controlled incoming alert goes through the same existing HUD and touch.
	var keep=g._first(0,"town_center")
	g.battle_alerts.record_hit(keep,1,g.tick_count)
	await settle()
	for p in [[Vector2i(320,568),104],[Vector2i(390,844),104],[Vector2i(568,320),54],[Vector2i(844,390),54]]:
		await resize(p[0]);assert_current_contract(str(p[0])+" alert",p[1])
	await resize(Vector2i(390,844))
	ck("390 portrait alert retains exact original four clock/control rectangles",g.time_label.get_global_rect()==Rect2(16,72,35,22) and g.pause_button.get_global_rect()==Rect2(61,60,60,46) and g.battle_jump_button.get_global_rect()==Rect2(131,60,54,46) and g.compact_menu_button.get_global_rect()==Rect2(195,60,60,46))
	await resize(Vector2i(568,320))
	ck("568 alert retains exact clock, pause, alert and menu coordinates",g.time_label.get_global_rect()==Rect2(313,22,35,22) and g.pause_button.get_global_rect()==Rect2(358,10,60,46) and g.battle_jump_button.get_global_rect()==Rect2(428,10,54,46) and g.compact_menu_button.get_global_rect()==Rect2(492,10,60,46))
	await tap(g.battle_jump_button)
	ck("ordinary attacked-keep camera jump remains reachable",g.camera_focus==keep.pos and g.command_sequence==seq and g.selected==selection)
	await resize(Vector2i(390,844))
	var old_menu=g.compact_menu_button.get_global_rect()
	var old_pause=g.pause_button.get_global_rect()
	var pt=old_menu.get_center()
	touch(0,pt,true);await frames()
	g.siege_challenge.wave=3;g.siege_challenge.active=[1]
	await settle()
	var new_menu=g.compact_menu_button.get_global_rect()
	ck("phase transition behind held finger never shifts pause or menu",new_menu==old_menu and old_pause==g.pause_button.get_global_rect())
	touch(0,pt,false);await frames()
	ck("held ordinary Menu still opens once, no message/action reroute",g.compact_menu.visible and g.mission_label.is_visible_in_tree() and g.command_sequence==seq)
	ck("wide and tight last wave never predicts another",g.survival_wave_status.text=="3/3 最後一波" and lexically_fits(g.survival_wave_status))
	ck("actual open final drawer agrees with HUD and no longer advertises another preparation",g.mission_label.text=="守城挑戰：第 3 / 3 波 · 最後一波；守住主堡並擊退增援。" and g.mission_label.is_visible_in_tree())
	g.ui.hide()
	ck("fully hidden battlefield HUD has no duplicate status overlay",not g.survival_wave_status.is_visible_in_tree())
	g.ui.show()
	g.siege_challenge.complete=true;g._check_end();await settle()
	ck("debrief title remains truthful and no persistent HUD wave leaks behind it",g.end_title.text=="三波守城成功" and g.end_panel.visible and not g.survival_wave_status.is_visible_in_tree())
	g.free()
	g=load("res://main.tscn").instantiate()
	g.skirmish_mode="survival";root.add_child(g);g.set_process(false);await settle()
	# Controlled occupancy: exercise actual director deny/retry, never
	# spawn, remove or force an actor. Restore the real candidate cell bits.
	var original={}
	for index in 64:
		var point=Vector3(8.5+2*(index%8),0,-3.5-2*(index/8))
		var cell=g._cell(point)
		original[cell]=g.navigation.is_point_solid(cell)
		g.navigation.set_point_solid(cell,true)
	var seen_before=g.entities.size();var before_bank=g.economy.bank_milli(0)
	g.tick_count=900;g._update_siege_challenge()
	await settle()
	ck("blocked real director refuses partial spawn with no commands or payment",g.siege_challenge.wave==0 and g.siege_challenge.active.is_empty() and g.commands.is_empty() and g.entities.size()==seen_before and g.economy.bank_milli(0)==before_bank)
	await tap(g.compact_menu_button);await settle()
	ck("actual waiting HUD and open drawer agree, not an indefinite zero-second promise",g.survival_wave_status.text=="1/3 待出發" and g.mission_label.is_visible_in_tree() and g.mission_label.text=="守城挑戰：第 1 / 3 波 · 待出發；可繼續整備。")
	await tap(g.compact_menu_button)
	for cell in original:g.navigation.set_point_solid(cell,original[cell])
	g.tick_count=919;g._update_siege_challenge();await settle()
	ck("awaiting actual next director boundary remains truthfully waiting",g.siege_challenge.wave==0 and g.survival_wave_status.text=="1/3 待出發")
	g.tick_count=920;g._update_siege_challenge();await settle()
	ck("restored real director retries on time, spawns exactly six and updates live phase",g.siege_challenge.wave==1 and g.siege_challenge.active.size()==6 and g.survival_wave_status.text=="1/3 迎擊" and g.commands.size()==1 and g.commands[0].type=="advance" and g.commands[0].team==1 and g.economy.bank_milli(0)==before_bank)
	g.free()
	g=load("res://main.tscn").instantiate()
	g.skirmish_mode="survival";root.add_child(g);g.set_process(false);await settle()
	g.tick_count=47200;g.game_time=2360.0;g.battle_speed=2.0
	await resize(Vector2i(390,844))
	ck("late 390 at 2× still shows the full new status while retaining the true overtime clock",fits(g.survival_wave_status) and lexically_fits(g.survival_wave_status) and g.time_label.text.begins_with("39:20") and g.time_label.text.contains("40s"))
	evidence["390 late overtime"]=snapshot()
	g.battle_alerts.record_hit(g._first(0,"town_center"),1,g.tick_count)
	await resize(Vector2i(320,568))
	ck("late alerted 320 at 2× anchors new status entirely inside normal viewport",fits(g.survival_wave_status) and lexically_fits(g.survival_wave_status) and g.time_label.text.begins_with("39:20") and g.time_label.text.contains("40s") and g.hud_top.size.y==104)
	evidence["320 late alerted overtime"]=snapshot()
	g.free()
	g=load("res://main.tscn").instantiate()
	g.skirmish_mode="breach";root.add_child(g);g.set_process(false);await settle()
	ck("another authored objective still exists, but no Survival overlay was constructed",g.objective_button.is_visible_in_tree() and not is_instance_valid(g.survival_wave_status) and g.ui.find_child("SurvivalWaveStatus",true,false)==null)
	finish()
