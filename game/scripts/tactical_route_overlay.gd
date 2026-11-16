extends Control
var game
func _process(_delta):queue_redraw()
func _draw():
 if not is_instance_valid(game) or not is_instance_valid(game.camera):return
 var points=[]
 if game.touch_command and game.unit_command_kind=="route":points=game.tactical_draft
 elif not game.selected.is_empty():
  var own=game.faction_views[0].get_record(game.selected[0])
  if own.get("owned",false):
   var ent=game._get_entity(game.selected[0])
   points=ent.get("tactical_points",[]).slice(ent.get("tactical_index",0))
 var previous=Vector2.INF
 for index in points.size():
  if game.camera.is_position_behind(points[index]):previous=Vector2.INF;continue
  var point=game.camera.unproject_position(points[index]+Vector3(0,.1,0))
  if previous!=Vector2.INF:draw_line(previous,point,Color(1,.85,.2,.65),2,true)
  draw_circle(point,10,Color(.08,.1,.12,.9))
  draw_arc(point,11,0,TAU,24,Color(1,.85,.2),2,true)
  draw_string(ThemeDB.fallback_font,point+Vector2(-4,5),str(index+1),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color.WHITE)
  previous=point
