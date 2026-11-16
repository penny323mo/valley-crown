extends SceneTree
const Backups=preload("res://scripts/checkpoint_backups.gd")
const Store=preload("res://scripts/checkpoint_store.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
var checks=[]
var dir="/tmp/vc-backups-"+str(Time.get_ticks_usec())
func check(label,ok):
 checks.append({"name":label,"passed":bool(ok)})
 if not ok:push_error(label)
func put(path,bytes):
 var f=FileAccess.open(path,FileAccess.WRITE);f.store_buffer(bytes);f.close()
func named(slot,bytes):
 var h=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes)
 return slot.get_file()+".preserved-"+h.finish().hex_encode()+".bin"
func _initialize():call_deferred("run")
func run():
 DirAccess.make_dir_recursive_absolute(dir)
 var shell=load("res://scripts/main_menu.gd").new();shell.checkpoint_path=dir+"/battle.bin";shell.expedition_checkpoint_path=dir+"/expedition.bin";root.add_child(shell);await process_frame
 shell.selected_mode="standard";shell._replace_match();var g=shell.match_node;g.set_process(false);g.test_mode=true
 for i in 40:g._tick(.05)
 shell._open_menu();shell._save_checkpoint()
 var canonical=FileAccess.get_file_as_bytes(shell.checkpoint_path);var saved=Codec.capture(g)
 check("manual same-build backup succeeds",Backups.keep(shell.checkpoint_path,g.Rules.BUILD_ID,false).ok)
 var list=Backups.list_slot(shell.checkpoint_path,g.Rules.BUILD_ID,false)
 check("listing is lazy and exposes only safe names",list.ok and list.entries.size()==1 and list.entries[0].keys()==["name"])
 var name=list.entries[0].name
 check("strict basename accepts generated SHA",Backups.valid_name(shell.checkpoint_path,name))
 check("path traversal rejected",not Backups.read(shell.checkpoint_path,"../"+name,g.Rules.BUILD_ID,false).ok)
 check("non-SHA name rejected",not Backups.valid_name(shell.checkpoint_path,"battle.bin.preserved-XYZ.bin"))
 check("uppercase SHA rejected",not Backups.valid_name(shell.checkpoint_path,name.to_upper()))
 check("backup bytes match canonical",FileAccess.get_file_as_bytes(dir.path_join(name))==canonical)
 check("backup reads exact snapshot",Backups.read(shell.checkpoint_path,name,g.Rules.BUILD_ID,false).data==saved)
 shell._inspect_checkpoint_backup(false,name)
 check("inspect exposes compatible load and caches no state",shell.backup_info.ok and not shell.backup_info.has("data") and shell.buttons.find_child("LoadBackupButton",true,false)!=null)
 shell._restore_checkpoint(false,name);var restored=shell.match_node;restored.set_process(false);restored.test_mode=true
 check("backup load replaces current game paused",restored!=g and restored.paused and Codec.capture(restored)==saved)
 check("load leaves canonical bytes unchanged",FileAccess.get_file_as_bytes(shell.checkpoint_path)==canonical)
 put(dir.path_join(name),"tampered".to_utf8_buffer());shell._restore_checkpoint(false,name)
 check("changed file between inspect and load rejected",shell.match_node==restored and FileAccess.get_file_as_bytes(shell.checkpoint_path)==canonical)
 put(dir.path_join(name),canonical)
 var data=saved.duplicate(true);data.build="synthetic-previous-version";var old=Codec.encode(data,data.build).bytes;var old_name=named(shell.checkpoint_path,old);put(dir.path_join(old_name),old)
 put(dir.path_join(name),old)
 check("valid payload under wrong SHA name rejected",Backups.read(shell.checkpoint_path,name,restored.Rules.BUILD_ID,false).reason=="BACKUP_HASH")
 put(dir.path_join(name),canonical)
 shell._inspect_checkpoint_backup(false,old_name)
 check("unknown build visible but not loadable",not shell.backup_info.ok and shell.backup_info.source_build==data.build and shell.buttons.find_child("LoadBackupButton",true,false)==null)
 check("ordinary backup rejected in expedition slot",not Backups.read(shell.checkpoint_path,name,restored.Rules.BUILD_ID,true).ok)
 check("unrelated files ignored",Backups.list_slot(shell.expedition_checkpoint_path,restored.Rules.BUILD_ID,true).entries.is_empty())
 # Synthetic names are listing-only files; no fixture serialized states are committed.
 for i in 30:put(dir.path_join("battle.bin.preserved-"+str(i).pad_zeros(64)+".bin"),PackedByteArray([1]))
 list=Backups.list_slot(shell.checkpoint_path,restored.Rules.BUILD_ID,false)
 var names=[]
 for e in list.entries:names.append(e.name)
 var sorted=names.duplicate();sorted.sort()
 check("bounded listing uses stable order and discloses truncation",list.entries.size()==24 and list.truncated and names==sorted)
 for size in [Vector2i(390,844),Vector2i(640,360),Vector2i(320,568)]:
  root.size=size
  for page in ["checkpoint","checkpoint_backups","checkpoint_backup_slot"]:
   shell.backup_index=1;shell._show_page(page);await process_frame;await process_frame
   var fit=true
   for button in shell.buttons.get_children():fit=fit and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()) and button.size.y>=44
   check(page+" buttons fit "+str(size),fit)
  shell._inspect_checkpoint_backup(false,name);await process_frame;await process_frame
  var fit=true
  for button in shell.buttons.get_children():fit=fit and Rect2(Vector2.ZERO,Vector2(size)).encloses(button.get_global_rect()) and button.size.y>=44
  check("detail buttons fit "+str(size),fit)
 var link_dir=dir+"/links";DirAccess.make_dir_absolute(link_dir)
 var link_slot=link_dir+"/battle.bin"
 var link_error=DirAccess.open(link_dir).create_link(dir.path_join(name),link_dir.path_join(name))
 check("symlink backup never loaded",link_error==OK and Backups.read(link_slot,name,restored.Rules.BUILD_ID,false).reason=="BACKUP_PATH")
 check("symlink excluded from listing",Backups.list_slot(link_slot,restored.Rules.BUILD_ID,false).entries.is_empty())
 var crowded=dir+"/crowded";DirAccess.make_dir_absolute(crowded)
 for i in 513:put(crowded.path_join(str(i)),PackedByteArray())
 check("scan limit fails closed",Backups.list_slot(crowded+"/battle.bin",restored.Rules.BUILD_ID,false).reason=="BACKUP_SCAN_LIMIT")
 var giant=dir+"/large";DirAccess.make_dir_absolute(giant)
 var f=FileAccess.open(giant.path_join(name),FileAccess.WRITE);f.seek(Codec.MAX_BYTES);f.store_8(0);f.close()
 check("oversized backup rejected before decode",Backups.read(giant+"/battle.bin",name,restored.Rules.BUILD_ID,false).reason=="SIZE")
 var failed=checks.filter(func(c):return not c.passed).size()
 print(JSON.stringify({"suite":"checkpoint_backups_contract","checks":checks,"failed":failed,"scope":"Dynamic isolated native states only; lazy local listing, hash-checked same-build restore, no migration or browser durability"}))
 shell.queue_free();await process_frame;quit(1 if failed else 0)
