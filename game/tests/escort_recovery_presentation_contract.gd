extends SceneTree
## Focused presentation/state matrix; real loss, spend and victory are
## separately proved by the full ordinary native Chapter 3 journey.
const Mission=preload("res://scripts/frontier_escort.gd")
const Rules=preload("res://scripts/rules.gd")
var game
var checks=[]
var geometry={}
var terminal={}
func _initialize():call_deferred("run")
func check(name,ok):
	checks.append({"name":name,"passed":bool(ok)})
	if not ok:push_error(name)
func frames():
	for i in 5:await process_frame
func view_shape(n):
	var r=n.get_global_rect();return [r.position.x,r.position.y,r.size.x,r.size.y]
func label_covered(node,margin=0):
	var font=node.get_theme_font("font")
	var px=node.get_theme_font_size("font_size")
	for c in node.text:
		if c!="\n" and not font.has_char(c.unicode_at(0)):return false
	for line in node.text.split("\n"):
		if font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,px).x+margin>node.size.x:return false
	return true
func tap(button):
	var pos=button.get_global_rect().get_center()
	for down in [true,false]:
		var ev=InputEventScreenTouch.new()
		ev.index=17;ev.position=pos;ev.pressed=down;root.push_input(ev)
		await process_frame
	await frames()
func settle():
	game._update_hud();game._layout_ui();await frames()
func villager(id):
	return {"id":id,"alive":true,"team":0,"kind":"villager","built":true,"pos":Vector3(-7,0,6),"cost_receipt_id":""}
func site(id,kind,p,paid=true,complete=true,team=0):
	return {"id":id,"alive":true,"team":team,"kind":kind,"built":complete,"pos":p,"cost_receipt_id":str("p",id) if paid else ""}
func hostile(id):
	return {"id":id,"alive":true,"team":1,"kind":"spearman","built":true,"pos":Vector3(0,0,4),"cost_receipt_id":""}
func recovery(pieces):
	var m=Mission.new()
	m.stage=2;m.villagers=[1,2,3];m.counter_ids=[101,102,103,104,105,106];m.launched=true
	m.update(200,[villager(1),villager(2),villager(3)]+pieces)
	return m
func state_checks():
	var m=Mission.new()
	check("opening exact authored title and arrival copy unchanged",m.stage_title()=="護送村民" and m.progress_text(0)=="村民 3/3 · 點此定位" and m.caption(0)=="護送拓荒隊 · 護送村民\n村民 3/3 · 倉庫 0/1 · 箭塔 0/1\n護送指定三名村民，至少一名抵達前哨。")
	m.stage=1
	check("ordinary first outpost build text unchanged",m.stage_title()=="建立前哨" and m.progress_text(0)=="倉庫 0/1 · 箭塔 0/1" and m.caption(0).ends_with("在前哨界線內放置倉庫和箭塔中心；付費完成才計算。"))
	m.stage=2;m.due=600
	check("pending counter has unchanged countdown and no premature rebuilding phase",m.stage_title()=="守住前哨" and m.progress_text(0)=="反攻 30 秒後出發" and m.progress_text(600)=="集結區受阻 · 等候出發" and not m.awaiting_outpost_rebuild())
	m.villagers=[1];m.counter_ids=[101,102,103,104,105,106];m.launched=true
	m.update(601,[villager(1),hostile(101)])
	check("a live enemy, even when both sites missing, keeps active battle text exactly unchanged",not m.awaiting_outpost_rebuild() and m.stage_title()=="守住前哨" and m.progress_text(601)=="村民 1/3 · 敵軍 1/6" and m.caption(601).ends_with("擊退餘下1名敵軍；前哨被毀可重建。"))
	var tower=site(21,"tower",Vector3(-5,0,7))
	var house=site(20,"storehouse",Vector3(-8,0,6))
	m.update(620,[villager(1),tower,site(22,"storehouse",Vector3(-8,0,6),true,false)])
	check("settled attack + unfinished paid site is still a missing warehouse, not a win",m.stage==2 and m.awaiting_outpost_rebuild() and m.progress_text(620)=="重建倉庫 0/1 · 箭塔 1/1")
	m.update(625,[villager(1),tower,site(22,"storehouse",Vector3(-2,0,6))])
	check("completed paid outside site cannot satisfy missing warehouse",m.stage==2 and m.awaiting_outpost_rebuild() and not m.buildings.has("storehouse"))
	m.update(630,[villager(1),tower,site(22,"storehouse",Vector3(-8,0,6),false)])
	check("inside but unearned site is not credited",m.stage==2 and m.awaiting_outpost_rebuild() and not m.buildings.has("storehouse"))
	m.update(640,[villager(1),tower,house])
	check("ordinary update grants terminal only once completed counted build exists",m.stage==3 and not m.awaiting_outpost_rebuild() and m.stage_title()=="任務完成" and m.progress_text(640)=="村民 1/3 · 敵軍 0/6" and m.caption(640).ends_with("村民與前哨存活，反攻全部擊退。"))
	m=Mission.new();m.stage=2;m.launched=true;m.villagers=[1]
	m.update(700,[house])
	check("zero living villagers never advertise a recoverable battle",m.living==0 and not m.awaiting_outpost_rebuild() and m.stage_title()=="守住前哨")

func layout_case(size,entry):
	root.size=size;await frames()
	var kind=entry[0];var pieces=entry[1];var line=entry[2];var need=entry[3]
	var m=recovery(pieces)
	game.frontier_escort=m
	await settle()
	var button=game.objective_button
	var viewport=root.get_visible_rect()
	var expected=game._objective_camera_prefix()+"護送拓荒隊 · 反攻已擊退\n"+line
	var p=str(size)+" "+kind
	check(p+" exact live next action and fully visible two-line authored objective",button.text==expected and button.is_visible_in_tree() and viewport.encloses(button.get_global_rect()) and game.hud_top.get_global_rect().encloses(button.get_global_rect()) and button.size.x>=44 and button.size.y==48 and label_covered(button,16))
	var before=game.command_sequence
	var bank=game.economy.bank_milli(0)
	var selected=game.selected.duplicate()
	await tap(button);await settle()
	check(p+" unchanged physical objective action only focuses known outpost",game.camera_focus==Mission.TARGET and game.command_sequence==before and game.economy.bank_milli(0)==bank and game.selected==selected and m.stage==2)
	await tap(game.compact_menu_button);await settle()
	var detail=game.mission_label
	var box=game.shortcut_scroll.get_global_rect()
	check(p+" actual drawer fully exposes paid, in-bound and complete requirement",game.compact_menu.visible and detail.is_visible_in_tree() and detail.text.begins_with("護送拓荒隊 · 反攻已擊退\n") and detail.text.ends_with("在前哨界線內付費重建"+need+"，完成才計。") and box.encloses(detail.get_global_rect()) and label_covered(detail))
	geometry[p]={"objective_rect":view_shape(button),"top_hud":view_shape(game.hud_top),"objective_text":button.text,"drawer_rect":view_shape(detail),"drawer_text":detail.text}
	var dismiss
	for b in game.compact_menu.find_children("*","Button",true,false):
		if b.text=="關閉":dismiss=b;break
	await tap(dismiss);await settle()
	check(p+" drawer close consumes no world action or spend",not game.compact_menu.visible and game.command_sequence==before and game.economy.bank_milli(0)==bank and game.selected==selected)

func terminal_case(size,reason):
	root.size=size
	game=load("res://main.tscn").instantiate()
	game.skirmish_mode="escort";root.add_child(game);game.set_process(false);game.test_mode=true
	await frames()
	var m=game.frontier_escort
	m.stage=2
	var initialized=m.launch([999901,999902,999903,999904,999905,999906])
	m.update(game.tick_count,game.entities)
	await settle()
	var label=str(size)+" "+reason
	var objective=game.objective_button
	var before=objective.text
	var box=objective.get_global_rect()
	check(label+" starts on verified live recovery presentation",initialized and m.awaiting_outpost_rebuild() and before.contains("重建倉庫 0/1 · 重建箭塔 0/1"))
	if reason=="surrender":game._submit("surrender")
	elif reason=="time_limit":game.tick_count=roundi(Rules.TIME_LIMIT/Rules.TICK)-1
	elif reason=="keep_destroyed":game._first(0,"town_center").hp=0
	elif reason=="escort_villagers_lost":
		for e in game.entities:
			if e.id in m.villagers:e.hp=0
	game._tick(Rules.TICK)
	# No extra frame or HUD refresh here: the result's very first paint
	# must already carry the baseline settled objective and drawer text.
	var prior_title=Mission.TITLES[2]
	var alive=0 if reason=="escort_villagers_lost" else 3
	var legacy_title=game._objective_camera_prefix()+"護送拓荒隊 · "+prior_title+"\n村民 %d/3 · 敵軍 0/6" % alive
	var legacy_drawer="護送拓荒隊 · "+prior_title+"\n村民 %d/3 · 倉庫 0/1 · 箭塔 0/1\n擊退餘下0名敵軍；前哨被毀可重建。" % alive
	var title={"surrender":"我方投降","time_limit":"戰事暫歇","keep_destroyed":"聚落失守","escort_villagers_lost":"拓荒隊失守"}[reason]
	var outcome="draw" if reason=="time_limit" else "defeat"
	check(label+" same actual terminal reason, result and presentation bounds",game.game_over and game.end_panel.is_visible_in_tree() and game.end_title.text==title and game.outcome==outcome and game.end_reason==reason and objective.get_global_rect()==box)
	check(label+" exact baseline title, legacy drawer and tooltip already restored on first terminal tick",objective.text==legacy_title and game.mission_label.text==legacy_drawer and objective.tooltip_text.ends_with(legacy_drawer) and m.awaiting_outpost_rebuild()==(alive>0))
	await frames()
	var area=game.end_panel.get_global_rect()
	terminal[label]={"before":before,"objective":objective.text,"drawer":game.mission_label.text,"tooltip":objective.tooltip_text,"title":title,"outcome":outcome,"reason":reason,"objective_rect":view_shape(objective),"report_rect":view_shape(game.end_panel),"objective_covered":area.encloses(objective.get_global_rect()),"model_fact_still_true":m.awaiting_outpost_rebuild()}
	await tap(game.find_child("InspectBattlefieldButton",true,false))
	check(label+" genuine aftermath touch keeps HUD and rebuild caption hidden",game.aftermath_view and not objective.is_visible_in_tree() and not game.mission_label.is_visible_in_tree())
	await tap(game.find_child("ReturnMatchReportButton",true,false))
	check(label+" actual return preserves terminal result and exact baseline copy",not game.aftermath_view and game.end_panel.is_visible_in_tree() and objective.text==legacy_title and game.mission_label.text==legacy_drawer and game.commands.is_empty())
	game.free();await frames()

func run():
	state_checks()
	root.size=Vector2i(568,320)
	game=load("res://main.tscn").instantiate()
	game.skirmish_mode="escort";root.add_child(game);game.set_process(false)
	await settle()
	var warehouse=site(20,"storehouse",Vector3(-8,0,6))
	var tower=site(21,"tower",Vector3(-5,0,7))
	var cases=[
		["warehouse only missing",[tower],"重建倉庫 0/1 · 箭塔 1/1","倉庫"],
		["tower only missing",[warehouse],"倉庫 1/1 · 重建箭塔 0/1","箭塔"],
		["both missing",[],"重建倉庫 0/1 · 重建箭塔 0/1","倉庫及箭塔"],
	]
	for size in [Vector2i(568,320),Vector2i(390,844)]:
		for entry in cases:await layout_case(size,entry)
	game.free();await frames()
	for size in [Vector2i(568,320),Vector2i(390,844),Vector2i(844,390)]:
		for reason in ["surrender","time_limit","keep_destroyed","escort_villagers_lost"]:await terminal_case(size,reason)
	var failed=checks.filter(func(x):return not x.passed).size()
	print(JSON.stringify({"suite":"escort_recovery_presentation_contract","checks":checks,"failed":failed,"geometry":geometry,"terminal":terminal,"scope":"Native routed UI and controlled precise objective input-state matrix; separate genuine loss/rebuild victory proof."}))
	quit(0 if failed==0 else 1)
