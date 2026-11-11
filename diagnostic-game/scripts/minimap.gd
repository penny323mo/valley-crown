extends Control
const Rules=preload("res://scripts/rules.gd")
var game: Node
func _draw():
	draw_style_box(_box(), Rect2(Vector2.ZERO, size))
	if not is_instance_valid(game): return
	var area = Rect2(Vector2(9,9), size-Vector2(18,18))
	draw_rect(area, Color("4f6550"))
	for e in game.faction_views[0].records().values():
		var p = Vector2((e.pos.x+Rules.MAP_HALF)/float(Rules.MAP_SIZE), (e.pos.z+Rules.MAP_HALF)/float(Rules.MAP_SIZE))*area.size+area.position
		var col = Color("d8c067") if e.team==0 else Color("e07762")
		if e.team==-1:
			col={"stone":Color("b8b8b2"),"iron":Color("bb9375")}.get(e.kind,Color("90aa64"))
		if e.remembered: col=Color("777b79")
		var r=3.3 if e.category=="building" else 1.7
		draw_circle(p,r,col)
	# Camera footprint follows real projected viewport corners at every zoom.
	# A fixed 74x50 pixel box would misrepresent the enlarged battlefield.
	var view_size=game.get_viewport().get_visible_rect().size
	var corners=PackedVector2Array()
	for screen in [Vector2.ZERO,Vector2(view_size.x,0),view_size,Vector2(0,view_size.y)]:
		var origin=game.camera.project_ray_origin(screen)
		var ray=game.camera.project_ray_normal(screen)
		if absf(ray.y)<0.00001: continue
		var point=origin+ray*(-origin.y/ray.y)
		var uv=Vector2((point.x+Rules.MAP_HALF)/float(Rules.MAP_SIZE),(point.z+Rules.MAP_HALF)/float(Rules.MAP_SIZE))
		corners.append(area.position+uv.clamp(Vector2.ZERO,Vector2.ONE)*area.size)
	if corners.size()==4:
		corners.append(corners[0]); draw_polyline(corners,Color(1,0.96,0.78,0.7),1.0,true)
func _gui_input(event):
	if (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT) or (event is InputEventScreenTouch and event.pressed):
		var uv=(event.position-Vector2(9,9))/(size-Vector2(18,18))
		game.camera_focus=Vector3(clampf(uv.x*Rules.MAP_SIZE-Rules.MAP_HALF,-Rules.CAMERA_LIMIT,Rules.CAMERA_LIMIT),0,clampf(uv.y*Rules.MAP_SIZE-Rules.MAP_HALF,-Rules.CAMERA_LIMIT,Rules.CAMERA_LIMIT))
		accept_event()
func _box():
	var b=StyleBoxFlat.new()
	b.bg_color=Color("172b2b")
	b.border_color=Color("837951")
	b.set_border_width_all(1)
	b.set_corner_radius_all(7)
	return b
