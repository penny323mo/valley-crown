extends Control
const Rules=preload("res://scripts/rules.gd")
var game: Node
const UNSEEN=Color("101c22")
const EXPLORED=Color("30453c")
const VISIBLE=Color("66866a")
var fog_image: Image
var fog_texture: ImageTexture
var fog_visible=PackedByteArray()
var fog_explored=PackedByteArray()
var fog_updates=0
var pointer={}
func _ready():
 visibility_changed.connect(_visibility_changed)
 texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
 tooltip_text="按住小地圖拖曳巡視；亮綠：目前視野，暗綠：曾探索，深色：未探索。"
func _visibility_changed():
 if not is_visible_in_tree() and not pointer.is_empty():pointer.valid=false
func _area():return Rect2(Vector2(9,9),size-Vector2(18,18))
func refresh_fog():
 if not is_instance_valid(game):return
 var visible=game.visible_cells[0];var explored=game.explored_cells[0]
 if visible.size()!=Rules.MAP_SIZE*Rules.MAP_SIZE or explored.size()!=visible.size():return
 if fog_texture!=null and visible==fog_visible and explored==fog_explored:return
 fog_visible=visible.duplicate();fog_explored=explored.duplicate()
 if fog_image==null:fog_image=Image.create(Rules.MAP_SIZE,Rules.MAP_SIZE,false,Image.FORMAT_RGB8)
 for i in visible.size():fog_image.set_pixel(i%Rules.MAP_SIZE,i/Rules.MAP_SIZE,VISIBLE if visible[i]!=0 else (EXPLORED if explored[i]!=0 else UNSEEN))
 if fog_texture==null:fog_texture=ImageTexture.create_from_image(fog_image)
 else:fog_texture.update(fog_image)
 fog_updates+=1;queue_redraw()
func cancel_pointer():pointer.clear()
func _jump(local):
 var uv=(local-_area().position)/_area().size
 game.camera_focus=Vector3(clampf(uv.x*Rules.MAP_SIZE-Rules.MAP_HALF,-Rules.CAMERA_LIMIT,Rules.CAMERA_LIMIT),0,clampf(uv.y*Rules.MAP_SIZE-Rules.MAP_HALF,-Rules.CAMERA_LIMIT,Rules.CAMERA_LIMIT))
func track_pointer(event,viewport):
 # Called after the game's global identity/epoch tracker, before GUI/world.
 # An owned stream is consumed to release even after leaving/hiding the map.
 if pointer.is_empty():return
 if not is_visible_in_tree() or game.paused or game.game_over:pointer.valid=false
 if pointer.kind=="touch":
  if game.touch_gesture or game.all_touch_ids.size()>1:pointer.valid=false
  if event is InputEventScreenTouch and event.index==pointer.id:
   if not event.pressed:cancel_pointer();viewport.set_input_as_handled()
   return
  if event is InputEventScreenDrag and event.index==pointer.id:
   var local=event.position-global_position
   if game.all_touch_ids.size()!=1 or game.touch_press_epochs.get(event.index,-1)!=pointer.epoch or not Rect2(Vector2.ZERO,size).has_point(local):pointer.valid=false
   if pointer.valid:_jump(local)
   viewport.set_input_as_handled()
 elif pointer.kind=="mouse":
  if not game.all_touch_ids.is_empty():pointer.valid=false
  if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
   cancel_pointer();viewport.set_input_as_handled()
  elif event is InputEventMouseMotion:
   var local=event.position-global_position
   if not (event.button_mask&MOUSE_BUTTON_MASK_LEFT) or not Rect2(Vector2.ZERO,size).has_point(local):pointer.valid=false
   if pointer.valid:_jump(local)
   viewport.set_input_as_handled()
func _draw():
 draw_style_box(_box(), Rect2(Vector2.ZERO, size))
 if not is_instance_valid(game): return
 var area = _area()
 if fog_texture==null:refresh_fog()
 if fog_texture!=null:draw_texture_rect(fog_texture,area,false)
 else:draw_rect(area,UNSEEN)
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
 if not is_instance_valid(game):return
 if event is InputEventScreenTouch or event is InputEventScreenDrag or event is InputEventMouseButton or event is InputEventMouseMotion:
  accept_event()
 if game.paused or game.game_over or not is_visible_in_tree():return
 if event is InputEventScreenTouch and event.pressed:
  if not pointer.is_empty():return
  if event.canceled or game.all_touch_ids.size()!=1 or event.index not in game.all_touch_ids or game.touch_gesture:return
  pointer={"kind":"touch","id":event.index,"epoch":game.touch_press_epochs.get(event.index,-1),"valid":true}
  _jump(event.position)
 elif event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
  if not pointer.is_empty():return
  if event.canceled or not game.all_touch_ids.is_empty():return
  pointer={"kind":"mouse","valid":true}
  _jump(event.position)
func _box():
 var b=StyleBoxFlat.new()
 b.bg_color=Color("172b2b")
 b.border_color=Color("837951")
 b.set_border_width_all(1)
 b.set_corner_radius_all(7)
 return b
