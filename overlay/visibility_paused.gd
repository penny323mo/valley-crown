extends Node
# DIAGNOSTIC ONLY: original main.tscn, then its real in-match Pause button at tick 0.
# No simulation, AI, frame cap, rendering-quality or product-source changes.
const WARMUP_USEC := 3000000
const MEASURE_USEC := 6000000
var game
var bridge_sink
var read_callback
var phase := "starting"
var first_draw_usec := -1
var begin := {}
var end := {}
var draw_samples := 0
var draw_call_sum := 0
var draw_call_min := 2147483647
var draw_call_max := 0
var process_monitor_seconds_sum := 0.0
var failure := ""

func _ready():
	if not OS.has_feature("web"): return
	# A private JS handle remains in Godot after removal from window. The exposed
	# immutable object has only read(); it cannot start/stop/reset/set game state.
	JavaScriptBridge.eval("""(()=>{let payload='{}',reader;const freeze=x=>{if(x&&typeof x==='object'){Object.values(x).forEach(freeze);Object.freeze(x)}return x};Object.defineProperty(window,'valleyVisibility',{value:Object.freeze({read:()=>{if(reader)reader();return freeze(JSON.parse(payload))}}),writable:false,configurable:false});window.__visibilityPrivateSink={publish:s=>{payload=s},bind:f=>{if(reader)throw Error('already bound');reader=f}}})()""")
	bridge_sink=JavaScriptBridge.get_interface("__visibilityPrivateSink")
	JavaScriptBridge.eval("delete window.__visibilityPrivateSink")
	game=load("res://main.tscn").instantiate()
	add_child(game)
	game.pause_button.pressed.emit()
	read_callback=JavaScriptBridge.create_callback(_read_report)
	bridge_sink.bind(read_callback)
	phase="warming"
	RenderingServer.frame_post_draw.connect(_after_draw)
	_publish()

func _invariant() -> bool:
	return game.paused and game.tick_count==0 and game.game_time==0.0 and game.tick_accumulator==0.0 and not game.game_over and not game.test_mode and game.ai_enabled and game.application_focused and not game.application_suspended and is_equal_approx(Engine.time_scale,1.0)

func _state() -> Dictionary:
	# All actor data comes only from the player's frozen public observation map.
	var records=game.faction_views[0].records()
	var ids=records.keys(); ids.sort()
	var observed := []
	for id in ids: observed.append(records[id])
	var public=game._snapshot().duplicate(true)
	public.erase("build"); public.erase("version")
	var size=get_viewport().get_visible_rect().size
	return {"public":public,"records_sha256":JSON.stringify(observed).sha256_text(),"record_count":observed.size(),"camera_focus":[game.camera_focus.x,game.camera_focus.y,game.camera_focus.z],"camera_position":[game.camera.position.x,game.camera.position.y,game.camera.position.z],"camera_rotation":[game.camera.rotation.x,game.camera.rotation.y,game.camera.rotation.z],"camera_size":game.camera.size,"viewport":[size.x,size.y],"content_scale_factor":get_window().content_scale_factor,"toast_visible":game.toast_label.visible,"toast_text":game.toast_label.text,"tutorial_visible":game.tutorial_panel.visible,"tutorial_text":game.tutorial_label.text,"pause_text":game.pause_button.text,"paused":game.paused,"ai_enabled":game.ai_enabled,"test_mode":game.test_mode,"engine_time_scale":Engine.time_scale,"engine_max_fps":Engine.max_fps,"focused":game.application_focused,"suspended":game.application_suspended}

func _sample() -> Dictionary:
	return {"wall_usec":Time.get_ticks_usec(),"process_frames":Engine.get_process_frames(),"product_process_frames":game.frame_counter,"drawn_frames":Engine.get_frames_drawn(),"state":_state()}

func _after_draw():
	if phase=="completed" or phase=="failed": return
	if not _invariant():
		failure="paused tick-zero runtime invariant changed"; phase="failed"; _publish(); return
	var now=Time.get_ticks_usec()
	if first_draw_usec<0: first_draw_usec=now
	if phase=="warming":
		if now-first_draw_usec<WARMUP_USEC: return
		begin=_sample(); phase="measuring"; return
	# Last completed engine frame monitor, not a hardware GPU command trace.
	var calls=int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	draw_samples+=1; draw_call_sum+=calls
	draw_call_min=mini(draw_call_min,calls); draw_call_max=maxi(draw_call_max,calls)
	process_monitor_seconds_sum+=Performance.get_monitor(Performance.TIME_PROCESS)
	if now-int(begin.wall_usec)>=MEASURE_USEC:
		end=_sample()
		phase="completed" if begin.state==end.state else "failed"
		if phase=="failed": failure="public scene or camera changed during measurement"
		_publish()

func _renderer() -> Dictionary:
	var info := {}
	for method in ["get_video_adapter_name","get_video_adapter_vendor","get_video_adapter_api_version","get_current_rendering_driver_name","get_current_rendering_method"]:
		info[method]=RenderingServer.call(method) if RenderingServer.has_method(method) else "unsupported"
	return info

func _read_report(_args):
	_publish()

func _publish():
	var report={"schema":"vc-paused-visibility-v1","diagnostic_only":true,"normal_gameplay_fps":false,"build":game.Rules.BUILD_ID,"game_source_sha256":FileAccess.get_sha256("res://scripts/game.gd"),"overlay_sha256":FileAccess.get_sha256("res://diagnostic/visibility_paused.gd"),"phase":phase,"failure":failure,"warmup_target_usec":WARMUP_USEC,"measurement_target_usec":MEASURE_USEC,"first_draw_usec":first_draw_usec,"begin":begin,"end":end,"draw_samples":draw_samples,"draw_call_sum":draw_call_sum,"draw_call_min":draw_call_min if draw_samples else null,"draw_call_max":draw_call_max if draw_samples else null,"process_monitor_seconds_sum":process_monitor_seconds_sum,"renderer":_renderer(),"observation_scope":"player observation only; immutable read bridge; no hidden actor authority","counter_scope":"ordinary paused product process and rendering, plus identical diagnostic observer overhead"}
	# Exported/remapped scripts may not expose their original source bytes.
	# Preserve FileAccess's raw result; never substitute a manifest/source echo.
	report.runtime_source_hash_status={"game_source_sha256":"unavailable" if report.game_source_sha256.is_empty() else "observed","overlay_sha256":"unavailable" if report.overlay_sha256.is_empty() else "observed"}
	report.current_state=_state()
	bridge_sink.publish(JSON.stringify(report))
