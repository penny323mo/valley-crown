extends RefCounted
## Local content-addressed backups only. No deletion, migration or slot overwrite.
const Codec=preload("res://scripts/checkpoint_codec.gd")
const Preservation=preload("res://scripts/checkpoint_preservation.gd")
const MAX_LIST=24
const MAX_SCAN=512
static func valid_name(slot:String,name:String)->bool:
 var prefix=slot.get_file()+".preserved-"
 if not name.begins_with(prefix) or not name.ends_with(".bin"):return false
 var digest=name.substr(prefix.length(),name.length()-prefix.length()-4)
 if digest.length()!=64:return false
 for c in digest:
  if c not in "0123456789abcdef":return false
 return true
static func keep(slot:String,build:String,expedition:bool)->Dictionary:
 if not FileAccess.file_exists(slot):return {"ok":false,"reason":"EMPTY"}
 return Preservation.preserve(slot,build,expedition,true)
static func read(slot:String,name:String,build:String,expedition:bool)->Dictionary:
 if not valid_name(slot,name):return {"ok":false,"reason":"BACKUP_NAME"}
 var directory=DirAccess.open(slot.get_base_dir())
 if directory==null or directory.is_link(name):return {"ok":false,"reason":"BACKUP_PATH"}
 var path=slot.get_base_dir().path_join(name)
 var f=FileAccess.open(path,FileAccess.READ)
 if f==null:return {"ok":false,"reason":"READ"}
 var size=f.get_length()
 if size<64 or size>Codec.MAX_BYTES:f.close();return {"ok":false,"reason":"SIZE"}
 var bytes=f.get_buffer(size);f.close()
 var h=HashingContext.new();h.start(HashingContext.HASH_SHA256);h.update(bytes)
 if name!=slot.get_file()+".preserved-"+h.finish().hex_encode()+".bin":return {"ok":false,"reason":"BACKUP_HASH"}
 var result=Codec.decode(bytes,build)
 if result.ok and (result.data.game.skirmish_mode=="expedition")!=expedition:return {"ok":false,"reason":"WRONG_SLOT"}
 return result
static func list_slot(slot:String,build:String,expedition:bool)->Dictionary:
 var directory=DirAccess.open(slot.get_base_dir())
 if directory==null:return {"ok":false,"reason":"READ","entries":[]}
 var names:Array[String]=[];var scanned=0
 directory.list_dir_begin()
 var name=directory.get_next()
 while name!="":
  scanned+=1
  if scanned>MAX_SCAN:directory.list_dir_end();return {"ok":false,"reason":"BACKUP_SCAN_LIMIT","entries":[]}
  if not directory.current_is_dir() and not directory.is_link(name) and valid_name(slot,name):names.append(name)
  name=directory.get_next()
 directory.list_dir_end();names.sort()
 var entries=[]
 for i in mini(names.size(),MAX_LIST):
  # Listing never reads or decodes snapshot payloads. Inspect exactly one on demand.
  entries.append({"name":names[i]})
 return {"ok":true,"entries":entries,"truncated":names.size()>MAX_LIST}
