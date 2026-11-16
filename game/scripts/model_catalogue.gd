extends Control
## Read-only model showroom. No battlefield, orders, economy or persistence.
const Rules=preload("res://scripts/rules.gd")
const ActionCharacter=preload("res://scripts/action_character.gd")
const ProgressionVisuals=preload("res://scripts/progression_visuals.gd")
const MatureVisuals=preload("res://assets/mature/visual_library.gd")
const AdvancedVisuals=preload("res://scripts/advanced_building_visuals.gd")
const TEAM=Color("435d6c")
var viewport:SubViewport
var image:TextureRect
var stage:Node3D
var pivot:Node3D
var camera:Camera3D
var actor
var model_kind=""
var yaw=0.0
var elapsed=0.0
var active=false
var pointer=-1
var pointer_origin=Vector2.ZERO
var yaw_origin=0.0
var touch_ids={}
var blocked=false
var mouse_drag=false
var gesture_mode=""
var scroll_request={}
var model_bounds=AABB()

func _ready():
 name="ModelCatalogue"
 custom_minimum_size=Vector2(0,230)
 size_flags_horizontal=Control.SIZE_EXPAND_FILL
 mouse_filter=Control.MOUSE_FILTER_IGNORE
 viewport=SubViewport.new();viewport.name="ModelViewport";viewport.size=Vector2i(640,360)
 viewport.own_world_3d=true;viewport.handle_input_locally=false;viewport.gui_disable_input=true
 viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
 add_child(viewport)
 stage=Node3D.new();viewport.add_child(stage)
 var environment=WorldEnvironment.new();environment.environment=Environment.new()
 environment.environment.background_mode=Environment.BG_COLOR
 environment.environment.background_color=Color("16272a")
 environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
 environment.environment.ambient_light_color=Color("d5e3e6");environment.environment.ambient_light_energy=0.8
 stage.add_child(environment)
 var light=DirectionalLight3D.new();light.rotation_degrees=Vector3(-42,-28,0);light.light_energy=1.4;stage.add_child(light)
 camera=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.keep_aspect=Camera3D.KEEP_HEIGHT;stage.add_child(camera)
 image=TextureRect.new();image.texture=viewport.get_texture();image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
 image.stretch_mode=TextureRect.STRETCH_SCALE;image.mouse_filter=Control.MOUSE_FILTER_STOP
 image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);image.offset_bottom=-26
 image.gui_input.connect(_mouse_input);add_child(image)
 var caption=Label.new();caption.text="實際模型 · 橫拖旋轉，直拖閱讀"
 caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;caption.add_theme_font_size_override("font_size",13)
 caption.mouse_filter=Control.MOUSE_FILTER_IGNORE;caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
 caption.offset_top=-24;add_child(caption)
 resized.connect(_resize_view)
 visibility_changed.connect(func():
  if not is_visible_in_tree():clear_model())
 set_process(false)

func _resize_view():
 cancel_input()
 if is_instance_valid(image):
  var ratio=maxf(0.5,size.x/maxf(1.0,size.y-26))
  viewport.size=Vector2i(640,clampi(roundi(640.0/ratio),180,640))
  _frame_model()

func show_model(kind:String) -> bool:
 clear_model()
 if not is_inside_tree() or not is_visible_in_tree():return false
 if kind not in Rules.UNIT_KINDS and kind not in ["town_center"]+Rules.BUILDABLE_KINDS:return false
 pivot=Node3D.new();pivot.name="CatalogueModel";stage.add_child(pivot)
 var model:Node3D
 if kind in ActionCharacter.KINDS:
  actor=ActionCharacter.new()
  if not actor.bind(pivot,kind,TEAM):clear_model();return false
 elif kind in ProgressionVisuals.UNIT_KINDS:
  ProgressionVisuals.build(pivot,kind,TEAM)
 elif kind in AdvancedVisuals.KINDS:
  model=AdvancedVisuals.instantiate_asset(kind,TEAM);pivot.add_child(model)
 else:
  model=MatureVisuals.instantiate_asset(kind,0,TEAM)
  if model==null:clear_model();return false
  pivot.add_child(model)
 model_kind=kind;elapsed=0.0;yaw=0.0
 model_bounds=_bounds(pivot)
 if not model_bounds.is_finite() or model_bounds.size.length_squared()<=0.0001:clear_model();return false
 _frame_model();set_yaw(0.4)
 active=true;viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS;set_process(true)
 return true

func _bounds(root:Node3D) -> AABB:
 var result=AABB();var first=true
 for node in root.find_children("*","MeshInstance3D",true,false):
  if node.mesh==null:continue
  var bounds=root.global_transform.affine_inverse()*node.global_transform*node.get_aabb()
  result=bounds if first else result.merge(bounds);first=false
 return result

func _frame_model():
 if not is_instance_valid(pivot) or model_bounds.size.length_squared()<=0:return
 var center=model_bounds.get_center()
 # All azimuths remain in frame; the footprint's diagonal covers long siege rigs.
 var radius=maxf(Vector2(model_bounds.size.x,model_bounds.size.z).length()*0.5,model_bounds.size.y*0.5)
 var aspect=float(viewport.size.x)/float(viewport.size.y)
 camera.size=maxf(1.5,radius*2.65/maxf(0.5,minf(1.0,aspect)))
 camera.position=center+Vector3(1.1,0.75,1.5).normalized()*maxf(5.0,radius*5.0)
 camera.look_at(center,Vector3.UP)
 camera.far=maxf(100.0,radius*10.0)

func set_yaw(value:float):
 if not is_finite(value) or not is_instance_valid(pivot):return
 yaw=wrapf(value,-PI,PI);pivot.rotation.y=yaw

func _process(delta):
 if not active or not is_visible_in_tree():return
 if not is_finite(delta) or delta<=0 or delta>0.25:return
 elapsed+=delta
 if actor!=null:
  # A static catalogue pose record, deliberately not a faction observation.
  actor.observe({"kind":model_kind,"pos":Vector3.ZERO,"last_seen_tick":int(elapsed*20),"visual_action":"idle"},delta,true)

func accepts_point(point:Vector2,clip:Rect2) -> bool:
 return active and is_visible_in_tree() and image.get_global_rect().intersection(clip).has_point(point)

func handle_touch(event:InputEvent,clip:Rect2) -> bool:
 if event is InputEventScreenTouch:
  if event.pressed:
   touch_ids[event.index]=true
   if event.canceled or touch_ids.size()>1:
    pointer=-1;blocked=true;mouse_drag=false;return false
   if not blocked and accepts_point(event.position,clip):
    pointer=event.index;pointer_origin=event.position;yaw_origin=yaw;gesture_mode="pending";scroll_request.clear();return true
  else:
   var owned=event.index==pointer
   touch_ids.erase(event.index)
   if owned:pointer=-1
   if event.canceled:blocked=true;pointer=-1
   if touch_ids.is_empty():blocked=false
   return owned
 elif event is InputEventScreenDrag and event.index==pointer:
  if blocked or touch_ids.size()!=1:pointer=-1;return false
  # Leaving the clipped preview cancels instead of turning it while scrolling.
  if not accepts_point(event.position,clip):pointer=-1;return true
  var distance=event.position-pointer_origin
  if gesture_mode=="pending":
   if distance.length()<8.0:return true
   if absf(distance.y)>absf(distance.x):
    scroll_request={"index":pointer,"origin":pointer_origin};pointer=-1;return false
   gesture_mode="rotate"
  set_yaw(yaw_origin+distance.x*0.012)
  return true
 return false

func _mouse_input(event):
 if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
  mouse_drag=event.pressed and active and touch_ids.is_empty()
  pointer_origin=event.position;yaw_origin=yaw;image.accept_event()
 elif event is InputEventMouseMotion and mouse_drag:
  if not event.button_mask&MOUSE_BUTTON_MASK_LEFT or not Rect2(Vector2.ZERO,image.size).has_point(event.position):mouse_drag=false;return
  set_yaw(yaw_origin+(event.position.x-pointer_origin.x)*0.012);image.accept_event()

func cancel_input(reset_touches:bool=false):
 if reset_touches:touch_ids.clear()
 pointer=-1;mouse_drag=false;blocked=not touch_ids.is_empty();gesture_mode="";scroll_request.clear()

func clear_model():
 cancel_input();touch_ids.clear();blocked=false;active=false;set_process(false)
 if is_instance_valid(viewport):viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
 if actor!=null:actor.release();actor=null
 if is_instance_valid(pivot):
  # Detach per-instance GPU geometry before releasing imported glTF nodes.
  # Shared meshes/materials stay immutable; this also avoids the dummy renderer
  # querying a disposed active material during headless native cleanup.
  for mesh in pivot.find_children("*","MeshInstance3D",true,false):mesh.mesh=null
  pivot.free()
 pivot=null;model_kind="";model_bounds=AABB()

func _notification(what):
 if what in [NOTIFICATION_APPLICATION_FOCUS_OUT,NOTIFICATION_APPLICATION_PAUSED]:cancel_input(true)

func _exit_tree():clear_model()

func set_entry(kind:String) -> bool:return show_model(kind)
func clear_entry():clear_model()
