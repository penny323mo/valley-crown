extends RefCounted
## One local, exact-build slot. No network, account, offline progress or migration.
const Preservation=preload("res://scripts/checkpoint_preservation.gd")
const Codec=preload("res://scripts/checkpoint_codec.gd")
const PATH="user://battle_checkpoint_v1.bin"
static func read_slot(build:String,path:String=PATH)->Dictionary:
 if not FileAccess.file_exists(path):return {"ok":false,"reason":"EMPTY"}
 var f=FileAccess.open(path,FileAccess.READ)
 if f==null:return {"ok":false,"reason":"READ"}
 var size=f.get_length()
 if size<=0 or size>Codec.MAX_BYTES:f.close();return {"ok":false,"reason":"SIZE"}
 var bytes=f.get_buffer(size);f.close()
 var result=Codec.decode(bytes,build)
 if result.ok and result.data.game.skirmish_mode=="expedition":return {"ok":false,"reason":"WRONG_SLOT"}
 return result
static func save_slot(game:Node,path:String=PATH)->Dictionary:
 if game.skirmish_mode=="escort":return {"ok":false,"reason":"護送任務暫不支援存檔"}
 if game.skirmish_mode=="expedition":return {"ok":false,"reason":"前線遠征暫不支援存檔"}
 if game.game_over or not game.paused:return {"ok":false,"reason":"NOT_PAUSED_MATCH"}
 var data=Codec.capture(game)
 var encoded=Codec.encode(data,game.Rules.BUILD_ID)
 if not encoded.ok:return encoded
 var preserved=Preservation.preserve(path,game.Rules.BUILD_ID)
 if not preserved.ok:return preserved
 var temp=path+".tmp"
 var f=FileAccess.open(temp,FileAccess.WRITE)
 if f==null:return {"ok":false,"reason":"WRITE"}
 f.store_buffer(encoded.bytes);f.flush();var error=f.get_error();f.close()
 if error!=OK:return {"ok":false,"reason":"WRITE"}
 var verify=read_slot(game.Rules.BUILD_ID,temp)
 if not verify.ok:return {"ok":false,"reason":"VERIFY"}
 if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path))!=OK:return {"ok":false,"reason":"RENAME"}
 return {"ok":true,"tick":data.game.tick_count,"preserved":preserved.preserved}
