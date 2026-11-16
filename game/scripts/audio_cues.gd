extends Node
const Policy=preload("res://scripts/audio_cue_policy.gd")
const STREAMS={"select":preload("res://assets/audio/select.wav"),"build":preload("res://assets/audio/build.wav"),"train":preload("res://assets/audio/train.wav"),"combat":preload("res://assets/audio/combat.wav")}
var policy=Policy.new()
var play_requests=0
var cue_counts={}
var last_cue=""
var player:AudioStreamPlayer
func _ready():
	player=AudioStreamPlayer.new(); player.volume_db=-9; add_child(player)
func configure(enabled:bool,blocked:bool):
	policy.enabled=enabled; policy.blocked=blocked
	if (not enabled or blocked) and is_instance_valid(player): player.stop()
func activate():
	# Called only by the user-operated audio toggle, never startup or a timer.
	policy.activated=true
func qa_status():
	return {"enabled":policy.enabled,"user_activated":policy.activated,"blocked":policy.blocked,"play_requests":play_requests,"cue_counts":cue_counts.duplicate(),"last_cue":last_cue,"player_playing":player.playing,"audibility":"unverified"}
func play_cue(kind):
	play_requests+=1; cue_counts[kind]=int(cue_counts.get(kind,0))+1; last_cue=kind
	player.stream=STREAMS[kind]; player.play()
func selection(records,ids,now_ms):
	for id in ids:
		var r=records.get(id,{})
		if r.get("owned",false) and r.get("alive",false) and not r.get("remembered",false):
			if policy.allow("select",now_ms): play_cue("select")
			return
func observe(records,tick,now_ms):
	for kind in policy.observe(records,tick,now_ms): play_cue(kind)
func reset():
	player.stop(); policy.reset(); play_requests=0; cue_counts.clear(); last_cue=""
