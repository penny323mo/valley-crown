extends SceneTree
const Store=preload("res://scripts/checkpoint_store.gd")
const Expedition=preload("res://scripts/expedition_checkpoint_store.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
var checks=[]
func check(name,ok):
 checks.append({"name":name,"passed":bool(ok)})
 if not ok:push_error(name)
func _initialize():call_deferred("run")
func run():
 var dir="/tmp/escort-boundary-"+str(Time.get_ticks_usec());DirAccess.make_dir_absolute(dir)
 var g=load("res://main.tscn").instantiate();g.skirmish_mode="escort";root.add_child(g);g.set_process(false);g.test_mode=true;g.paused=true
 await process_frame
 for expedition in [false,true]:
  var path=dir+("/expedition.bin" if expedition else "/ordinary.bin")
  var original="synthetic protected sentinel".to_utf8_buffer()
  var f=FileAccess.open(path,FileAccess.WRITE);f.store_buffer(original);f.close()
  var result=Expedition.save_slot(g,path) if expedition else Store.save_slot(g,path)
  check("unsupported escort refuses existing slot "+str(expedition),not result.ok and result.reason=="護送任務暫不支援存檔")
  check("original bytes untouched "+str(expedition),FileAccess.get_file_as_bytes(path)==original)
  check("no temporary or preservation files "+str(expedition),not FileAccess.file_exists(path+".tmp") and DirAccess.get_files_at(dir).size()==(2 if expedition else 1))
 check("codec refuses capture of unsupported escort",not Codec.capture_result(g).ok)
 var normal=load("res://main.tscn").instantiate();root.add_child(normal);normal.set_process(false);normal.test_mode=true
 await process_frame
 var snapshot=Codec.capture(normal);snapshot.game.skirmish_mode="escort"
 check("codec refuses fabricated escort mode in normal schema",not Codec.validate(snapshot))
 check("encoder cannot serialize missing mission state",not Codec.encode(snapshot,normal.Rules.BUILD_ID).ok)
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"escort_storage_boundary_contract","checks":checks,"failed":failed,"scope":"Dynamic isolated sentinels and fresh states; unsupported escort blocked before save I/O and by codec; no private samples or migration"}))
 g.free();normal.free();quit(1 if failed else 0)
