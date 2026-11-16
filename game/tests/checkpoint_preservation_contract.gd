extends SceneTree
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Guard=preload("res://scripts/checkpoint_preservation.gd")
const Store=preload("res://scripts/checkpoint_store.gd")
const Expedition=preload("res://scripts/expedition_checkpoint_store.gd")
var checks=[]
var dir="/tmp/vc-preserve-"+str(Time.get_ticks_usec())
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func put(path,bytes):
 var f=FileAccess.open(path,FileAccess.WRITE);f.store_buffer(bytes);f.close()
func getbytes(path):return FileAccess.get_file_as_bytes(path)
func backup(path,bytes):
 var h=HashingContext.new();h.start(HashingContext.HASH_SHA256)
 if not bytes.is_empty():h.update(bytes)
 return path+".preserved-"+h.finish().hex_encode()+".bin"
func _initialize():call_deferred("run")
func run():
 DirAccess.make_dir_recursive_absolute(dir)
 var g=load("res://main.tscn").instantiate();root.add_child(g);g.set_process(false);g.test_mode=true;g.paused=true
 await process_frame
 var path=dir+"/ordinary.bin"
 check("empty slot needs no backup",Guard.preserve(path,g.Rules.BUILD_ID)=={"ok":true,"preserved":false})
 check("fresh isolated ordinary save",Store.save_slot(g,path).ok)
 var current=getbytes(path)
 check("same-build slot remains unchanged",Guard.preserve(path,g.Rules.BUILD_ID)=={"ok":true,"preserved":false} and getbytes(path)==current)
 var old=Codec.capture(g);old.build="synthetic-previous-version"
 var encoded=Codec.encode(old,old.build)
 check("synthetic old snapshot encodes",encoded.ok)
 put(path,encoded.bytes)
 var mismatch=Store.read_slot(g.Rules.BUILD_ID,path)
 check("unknown build still rejected with explicit versions",not mismatch.ok and mismatch.reason=="BUILD_MISMATCH" and mismatch.source_build==old.build and mismatch.expected_build==g.Rules.BUILD_ID)
 var b=backup(path,encoded.bytes)
 check("incompatible source backed up byte-for-byte",Guard.preserve(path,g.Rules.BUILD_ID).preserved and getbytes(path)==encoded.bytes and getbytes(b)==encoded.bytes)
 check("identical backup reused",Guard.preserve(path,g.Rules.BUILD_ID).ok and getbytes(b)==encoded.bytes)
 var saved=Store.save_slot(g,path)
 check("save replaces only after backup",saved.ok and saved.preserved and Store.read_slot(g.Rules.BUILD_ID,path).ok and getbytes(b)==encoded.bytes)
 put(path,encoded.bytes);put(b,"different bytes".to_utf8_buffer())
 var denied=Store.save_slot(g,path)
 check("conflicting backup blocks overwrite",not denied.ok and denied.reason=="BACKUP_CONFLICT" and getbytes(path)==encoded.bytes and getbytes(b)=="different bytes".to_utf8_buffer())
 var corrupt="not a checkpoint".to_utf8_buffer();put(path,corrupt)
 check("corrupt slot preserved before replacement",Store.save_slot(g,path).ok and getbytes(backup(path,corrupt))==corrupt)
 var empty=PackedByteArray();put(path,empty)
 check("empty existing file retained as backup",Store.save_slot(g,path).ok and FileAccess.file_exists(backup(path,empty)))
 var unreadable=dir+"/blocked.bin";put(unreadable,corrupt)
 DirAccess.make_dir_absolute(backup(unreadable,corrupt))
 check("backup write failure retains original",not Store.save_slot(g,unreadable).ok and getbytes(unreadable)==corrupt)
 var e=load("res://main.tscn").instantiate();e.skirmish_mode="expedition";root.add_child(e);e.set_process(false);e.test_mode=true;e.paused=true
 await process_frame
 var ep=dir+"/expedition.bin";var ed=Codec.capture(e);ed.build="synthetic-expedition-previous";var eb=Codec.encode(ed,ed.build).bytes;put(ep,eb)
 var ord_before=getbytes(path)
 check("expedition old slot preserved independently",Expedition.save_slot(e,ep).ok and getbytes(backup(ep,eb))==eb and getbytes(path)==ord_before)
 check("expedition cannot target ordinary canonical slot",Expedition.save_slot(e,Store.PATH).reason=="ORDINARY_SLOT_PROTECTED")
 check("ordinary writer rejects expedition",not Store.save_slot(e,path).ok and getbytes(path)==ord_before)
 var fail=0
 for c in checks:
  if not c.passed:fail+=1
 print(JSON.stringify({"suite":"checkpoint_preservation_contract","passed":checks.size()-fail,"failed":fail,"checks":checks,"scope":"Only synthetic snapshots and isolated temporary paths; no user samples, cross-version migration or browser durability claims"}))
 g.free();e.free();quit(1 if fail else 0)
