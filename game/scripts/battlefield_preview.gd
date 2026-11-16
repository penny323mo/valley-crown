extends Control
## Public authored layout diagram, not a live minimap or enemy-visibility source.
const Layout=preload("res://scripts/battlefield_layout.gd")
var layout_id="valley"
func _ready():
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 custom_minimum_size=Vector2(0,190)
 resized.connect(queue_redraw)
func configure(id:String):
 layout_id=Layout.valid(id);queue_redraw()
func project(p:Vector3)->Vector2:
 var side=minf(size.x-16,170)
 return Vector2(size.x/2,91)+Vector2(p.x,p.z)*(side/80.0)
func _draw():
 draw_rect(Rect2(Vector2.ZERO,size),Color("151e1b"))
 var side=minf(size.x-16,170)
 draw_rect(Rect2(Vector2(size.x/2-side/2,91-side/2),Vector2(side,side)),Color("46513a"))
 for resource in Layout.expansion_resources(layout_id)+Layout.mineral_resources(layout_id):
  var color=Color("99b862") if resource.kind in ["pine","oak"] else Color("d6a565") if resource.kind=="berry" else Color("c4c4b5") if resource.kind=="stone" else Color("a78160")
  draw_circle(project(resource.pos),2.4,color)
 for team in 2:
  var home=Vector3(-25,0,24)*(1 if team==0 else -1)
  draw_rect(Rect2(project(home)-Vector2(4,4),Vector2(8,8)),Color("81aab6") if team==0 else Color("bd6c57"))
 var font=get_theme_default_font()
 draw_string(font,Vector2(8,185),"PUBLIC LAYOUT · bases / expansion resources",HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("e4dfcb"))
