extends SceneTree
## Routed native viewport checks over a controlled completed Breach report.
## The natural journey is separate; do not claim battle or hardware here.
const Report=preload("res://scripts/match_report.gd")
var checks=[]
var geometry={}
var game
var next_signals=0

func _initialize():call_deferred("run")
func check(label,ok):
	checks.append({"name":label,"passed":bool(ok)})
	if not ok:push_error(label)
func frames(n=5):
	for i in n:await process_frame
func touch(index,p,pressed):
	var ev=InputEventScreenTouch.new()
	ev.index=index;ev.position=p;ev.pressed=pressed
	root.push_input(ev)
func drag_event(index,p,start):
	var ev=InputEventScreenDrag.new()
	ev.index=index;ev.position=p;ev.relative=p-start
	root.push_input(ev)
func tap(node):
	var p=node.get_global_rect().get_center()
	touch(0,p,true);await process_frame;touch(0,p,false);await frames()
func drag(start,finish):
	touch(0,start,true);await process_frame
	drag_event(0,finish,start);await process_frame
	touch(0,finish,false);await frames()
func role_rect(control):
	var r=control.get_global_rect()
	return [r.position.x,r.position.y,r.size.x,r.size.y]
func has_font_chars(control):
	var font=control.get_theme_font("font")
	for point in control.text:
		if point!="\n" and not font.has_char(point.unicode_at(0)):return false
	return true
func fully_reachable(control):
	var r=control.get_global_rect()
	return control.is_visible_in_tree() and root.get_visible_rect().encloses(r) and game.end_panel.get_global_rect().encloses(r) and r.size.x>=44 and r.size.y>=44
func report_visible_height():
	return game.end_report_label.get_global_rect().intersection(game.end_scroll.get_global_rect()).size.y
func line_height():
	var label=game.end_report_label
	return label.get_theme_font("font").get_height(label.get_theme_font_size("font_size"))+label.get_theme_constant("line_spacing")
func layout(size):
	root.size=size
	await frames()
	game._layout_ui()
	await frames()
func capture_layout(expected_columns,expected_height):
	var label=str(root.size)
	var actions=game.end_actions.get_children()
	check(label+" expected grid columns",game.end_actions.columns==expected_columns)
	check(label+" report has expected scrollable height",game.end_scroll.size.y==expected_height)
	check(label+" four ≥44px actions fully visible with covered text",actions.size()==4 and actions.all(func(a):return fully_reachable(a) and has_font_chars(a)))
	check(label+" tabs and actions do not overlap scroll lane",not game.end_tabs.get_global_rect().intersects(game.end_scroll.get_global_rect()) and not game.end_actions.get_global_rect().intersects(game.end_scroll.get_global_rect()))
	var bounds=actions.map(func(a):return a.get_global_rect())
	var disjoint=true
	for i in bounds.size():
		for j in range(i+1,bounds.size()):
			disjoint=disjoint and not bounds[i].intersects(bounds[j])
	check(label+" actions are physically disjoint",disjoint)
	geometry[label]={"columns":game.end_actions.columns,"scroll":role_rect(game.end_scroll),"actions":actions.map(role_rect),"visible_report_px":report_visible_height()}
func finish():
	var failed=checks.filter(func(x):return not x.passed).size()
	print(JSON.stringify({"suite":"compact_victory_report_contract","checks":checks,"failed":failed,"geometry":geometry,"scope":"Controlled finished result, routed native viewport touch and resize; not natural or physical phone."}))
	game.free();quit(1 if failed else 0)
func run():
	root.size=Vector2i(568,320)
	game=load("res://main.tscn").instantiate()
	game.skirmish_mode="breach";game.campaign_chapter=0
	root.add_child(game);game.set_process(false);game.test_mode=true
	game.campaign_next_requested.connect(func():next_signals+=1)
	await frames()
	game.tick_count=900
	game.match_report.record_completion({"id":991,"team":0,"kind":"house","category":"building","alive":true,"built":true},110)
	game.match_report.record_training({"id":992,"team":0,"kind":"spearman","category":"unit","alive":true},260)
	game.breach_mission.stage=2
	game._check_end()
	await layout(Vector2i(568,320))
	capture_layout(4,116)
	var initial=game.end_report_label.text
	var compact_rows=initial.split("\n")
	var canonical=Report.page_text(game.last_match_report,"overview")
	var canonical_rows=canonical.split("\n")
	var compact_facts=Array(compact_rows).filter(func(x):return not x.is_empty())
	var canonical_facts=Array(canonical_rows).filter(func(x):return not x.is_empty())
	compact_facts.sort();canonical_facts.sort()
	check("first real milestone is raised without losing or duplicating canonical facts",compact_rows[0]=="本局階段紀錄" and compact_rows[1].contains("首次完工 · 民居") and report_visible_height()>=2*line_height() and compact_facts==canonical_facts)
	check("mission result and all explanation remain readable on native Overview",game.end_title.text=="攻城突破完成" and game.end_body.is_visible_in_tree() and game.end_body.text.contains("前哨箭塔及敵方主堡已摧毀") and game.end_scroll.get_global_rect().encloses(game.end_body.get_global_rect()) and has_font_chars(game.end_title) and has_font_chars(game.end_body))
	check("canonical history format still begins with map, hides no facts",canonical_rows[0].begins_with("戰場：") and canonical.contains("首次出兵 · 長槍兵") and game.last_match_report.outcome=="victory")
	var next=game.end_setup_button
	var region=game.end_scroll.get_global_rect()
	var from=region.get_center()+Vector2(0,region.size.y*.40)
	var up=region.get_center()-Vector2(0,region.size.y*.40)
	await drag(from,up)
	var seq=game.command_sequence
	check("single finger moves true report sharing no world or Next action",game.end_scroll.scroll_vertical>=90 and next_signals==0 and game.commands.is_empty())
	var start=next.get_global_rect().get_center()
	await drag(start,start+Vector2(25,0))
	check("drag originating inside Next cannot count as a press",next_signals==0 and game.end_panel.visible and game.command_sequence==seq)
	await drag(region.get_center(),start)
	check("report drag crossing Next cannot count as a press",next_signals==0 and game.end_panel.visible and game.command_sequence==seq)
	var before_multi=game.end_scroll.scroll_vertical
	touch(0,start,true);await process_frame
	touch(1,from,true);await process_frame
	drag_event(1,up,from);await process_frame
	touch(1,up,false);await process_frame
	touch(0,start,false);await frames()
	check("two fingers quarantine Next and report drag until complete release",next_signals==0 and game.all_touch_ids.is_empty() and game.command_sequence==seq and game.end_scroll.scroll_vertical==before_multi)
	var page_headers={"economy":"食：","units":"村民","buildings":"主堡"}
	for i in range(1,4):
		var tab=game.end_tabs.get_child(i)
		await tap(tab)
		var p=tab.get_meta("report_page")
		var lines=game.end_report_label.text.split("\n")
		check("actual "+p+" tab opens with immediate full first data row and no repeated explanation",game.end_report_page==p and not game.end_body.is_visible_in_tree() and game.end_scroll.scroll_vertical==0 and report_visible_height()>=3*line_height() and lines[2].begins_with(page_headers[p]) and game.end_report_label.text==Report.page_text(game.last_match_report,p))
	check("all three tabs keep original result and cannot trigger Next",next_signals==0 and game.game_over and game.tick_count==900)
	touch(0,next.get_global_rect().get_center(),true);await process_frame
	await layout(Vector2i(390,844))
	touch(0,next.get_global_rect().get_center(),false);await frames()
	check("held Next release after rotation is quarantined",next_signals==0 and game.all_touch_ids.is_empty() and game.end_panel.visible)
	capture_layout(2,328)
	check("portrait retains existing selected detail and visible original explanation",game.end_report_page=="buildings" and game.end_body.is_visible_in_tree())
	await tap(game.end_tabs.get_child(0))
	check("portrait overview restores exact canonical order",game.end_report_label.text==canonical)
	await layout(Vector2i(320,568));capture_layout(2,312)
	check("small portrait retains body and canonical report",game.end_body.is_visible_in_tree() and game.end_report_label.text==canonical)
	await layout(Vector2i(440,320));capture_layout(2,64)
	check("too-narrow landscape retains safe two rows and original report",not game.end_compact_summary and game.end_report_label.text==canonical)
	await layout(Vector2i(1280,720));capture_layout(2,328)
	check("normal desktop retains original report and action layout",not game.end_compact_summary and game.end_report_label.text==canonical)
	await layout(Vector2i(844,390));capture_layout(4,186)
	check("wide low landscape retains complete mission explanation and visible milestones",game.end_body.is_visible_in_tree() and report_visible_height()>=2*line_height())
	await layout(Vector2i(568,320))
	touch(0,next.get_global_rect().get_center(),true);await process_frame
	await layout(Vector2i(844,390))
	touch(0,next.get_global_rect().get_center(),false);await frames()
	check("held Next release after compact-to-compact resize quarantined",next_signals==0 and game.all_touch_ids.is_empty())
	await layout(Vector2i(568,320))
	await tap(next)
	check("fresh ordinary Next touch after swipes, pair, and rotation fires exactly once",next_signals==1 and game.command_sequence==seq and game.commands.is_empty() and game.tick_count==900)
	finish()
