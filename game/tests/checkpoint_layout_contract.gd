extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Restore=preload("res://scripts/checkpoint_restore.gd")
const Store=preload("res://scripts/checkpoint_store.gd")
var checks=[]
var resource_layouts={}
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func _initialize():call_deferred("run")
func make_game(layout,mode="standard"):
 var g=load("res://main.tscn").instantiate()
 g.layout_id=layout;g.skirmish_mode=mode;g.victory_mode="conquest"
 g.history_path="/tmp/layout-contract-history-"+str(Time.get_ticks_usec())+".json"
 root.add_child(g);g.set_process(false);g.test_mode=true
 return g
func run():
 for layout in ["valley","woodland"]:
  for mode in ["practice","standard","pressure"]:
   var g=make_game(layout,mode);await process_frame
   for i in 40:g._tick(.05)
   var captured=Codec.capture_result(g)
   var label=layout+"/"+mode
   resource_layouts[label]=g.entities.filter(func(e):return e.team==-1).map(func(e):return [e.kind,e.pos])
   check(label+" captures explicit world identity",captured.ok and captured.data.game.layout_id==layout)
   if not captured.ok:g.free();continue
   var encoded=Codec.encode(captured.data,g.Rules.BUILD_ID)
   var decoded=Codec.decode(encoded.get("bytes",PackedByteArray()),g.Rules.BUILD_ID)
   check(label+" exact build roundtrip",encoded.ok and decoded.ok and decoded.data.game.layout_id==layout)
   var h=make_game(layout,mode);await process_frame
   var applied=Restore.apply(h,captured.data)
   check(label+" restores exact entity world",applied and Codec.capture(h)==captured.data)
   h.paused=false
   for i in 40:g._tick(.05);h._tick(.05)
   check(label+" ordinary continuation identical",Codec.capture(g)==Codec.capture(h) and h.economy.audit().ok)
   h.free();g.free()
 for mode in ["practice","standard","pressure"]:
  check(mode+" restores genuinely distinct resource layouts",resource_layouts["valley/"+mode]!=resource_layouts["woodland/"+mode])
 var g=make_game("valley");await process_frame
 var baseline=Codec.capture(g)
 for bad in ["unknown","",42,null]:
  var invalid=baseline.duplicate(true);invalid.game.layout_id=bad
  check("invalid layout rejected "+str(bad),not Codec.validate(invalid) and not Codec.encode(invalid,g.Rules.BUILD_ID).ok)
 var absent=baseline.duplicate(true);absent.game.erase("layout_id")
 check("missing layout never guessed from entities",not Codec.validate(absent))
 for mode in ["battle","fortress","survival","expedition"]:
  var invalid=baseline.duplicate(true);invalid.game.layout_id="woodland";invalid.game.skirmish_mode=mode
  check("unsupported woodland mode rejected "+mode,not Codec.validate(invalid))
 for victory in ["control","supply"]:
  var invalid=baseline.duplicate(true);invalid.game.layout_id="woodland";invalid.game.victory_mode=victory
  check("unsupported woodland objective rejected "+victory,not Codec.validate(invalid))
 var other=make_game("woodland");await process_frame
 var other_data=Codec.capture(other);var before=Codec.capture(g)
 check("wrong prepared candidate rejected",not Restore.apply(g,other_data))
 check("mismatched restore leaves candidate untouched",Codec.capture(g)==before)
 var prior=baseline.duplicate(true);prior.build="older-unrecognized-build"
 check("exact build restriction retained",not Codec.encode(prior,g.Rules.BUILD_ID).ok and not Restore.apply(g,prior))
 var path="/tmp/layout-contract-"+str(Time.get_ticks_usec())+".bin"
 g.paused=true
 var saved=Store.save_slot(g,path)
 check("fresh isolated canonical slot saved",saved.ok)
 var bytes=FileAccess.get_file_as_bytes(path)
 g.layout_id="unknown"
 var rejected=Store.save_slot(g,path)
 check("invalid new layout cannot overwrite old slot",not rejected.ok and FileAccess.get_file_as_bytes(path)==bytes)
 g.layout_id="valley"
 check("isolated history untouched",not FileAccess.file_exists(g.history_path))
 other.free();g.free()
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"checkpoint_layout_contract","checks":checks,"failed":failed,"scope":"Dynamically generated isolated layouts and exact-build snapshots; strict identity and candidate preparation, no historical sample or migration"}))
 quit(1 if failed else 0)
