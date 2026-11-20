extends Control
## Public authored layout diagram, not a live minimap or enemy-visibility source.
const RIVER_LABEL_FONT=preload("res://assets/fonts/ui_tc.otf")
const Layout=preload("res://scripts/battlefield_layout.gd")
var layout_id="valley"
var compact_setup=false
func _ready():
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 custom_minimum_size=Vector2(0,190)
 resized.connect(queue_redraw)
func configure(id:String):
 layout_id=Layout.valid(id);queue_redraw()
func set_compact_setup(enabled:bool):
 if compact_setup==enabled:return
 compact_setup=enabled
 custom_minimum_size.y=114 if enabled else 190
 queue_redraw()
func _side()->float:
 return minf(size.x-16,88 if compact_setup else (98 if layout_id==Layout.River.ID else 170))
func _middle()->float:
 return 50 if compact_setup else (71 if layout_id==Layout.River.ID else 91)
func project(p:Vector3)->Vector2:
 return Vector2(size.x/2,_middle())+Vector2(p.x,p.z)*(_side()/80.0)
func _draw():
 draw_rect(Rect2(Vector2.ZERO,size),Color("151e1b"))
 var side=_side()
 var mid=_middle()
 draw_rect(Rect2(Vector2(size.x/2-side/2,mid-side/2),Vector2(side,side)),Color("46513a"))
 if layout_id==Layout.River.ID:
  _band(-40.0,40.0,Color("315a64"))
  _band(Layout.River.BRIDGE_X_MIN,Layout.River.BRIDGE_X_MAX,Color("bd8a57"))
  _band(Layout.River.FORD_X_MIN,Layout.River.FORD_X_MAX,Color("8caa94"))
 for resource in Layout.expansion_resources(layout_id)+Layout.mineral_resources(layout_id):
  var color=Color("99b862") if resource.kind in ["pine","oak"] else Color("d6a565") if resource.kind=="berry" else Color("c4c4b5") if resource.kind=="stone" else Color("a78160")
  if layout_id=="iron_crossroads" and resource.kind=="iron" and maxf(absf(resource.pos.x),absf(resource.pos.z))<5:
   draw_circle(project(resource.pos),4.0,Color("f2b36d"),false,1.0,true)
   color=Color("ee865e")
  draw_circle(project(resource.pos),2.4,color)
 for team in 2:
  var home=Vector3(-25,0,24)*(1 if team==0 else -1)
  draw_rect(Rect2(project(home)-Vector2(4,4),Vector2(8,8)),Color("81aab6") if team==0 else Color("bd6c57"))
 var font=get_theme_default_font()
 var legend="中間圈起的是前線鐵礦 · 兩翼另有糧石" if layout_id=="iron_crossroads" else "PUBLIC LAYOUT · bases / expansion resources"
 if layout_id==Layout.River.ID:
  draw_string(RIVER_LABEL_FONT,Vector2(8,108 if compact_setup else 14),"木橋／淺灘" if compact_setup else "雙渡河谷 · 木橋／淺灘",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("e4dfcb"))
 else:
  draw_string(font,Vector2(8,108 if compact_setup else 185),legend,HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("e4dfcb"))
func _band(left:float,right:float,color:Color):
 var a=project(Vector3(left,0,Layout.River.BANK_Z_MIN))
 var b=project(Vector3(right,0,Layout.River.BANK_Z_MAX))
 draw_rect(Rect2(a,b-a),color)
