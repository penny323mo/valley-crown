extends RefCounted
## Preserve bytes locally before replacing an incompatible slot. No migration.
const Codec=preload("res://scripts/checkpoint_codec.gd")
static func preserve(path:String,build:String,expedition:bool=false)->Dictionary:
 if not FileAccess.file_exists(path):return {"ok":true,"preserved":false}
 var old=FileAccess.open(path,FileAccess.READ)
 if old==null:return {"ok":false,"reason":"BACKUP_READ"}
 var size=old.get_length()
 if size>Codec.MAX_BYTES:old.close();return {"ok":false,"reason":"BACKUP_SIZE"}
 var bytes=old.get_buffer(size);var error=old.get_error();old.close()
 if bytes.size()!=size or error not in [OK,ERR_FILE_EOF]:return {"ok":false,"reason":"BACKUP_READ"}
 var decoded=Codec.decode(bytes,build)
 if decoded.ok and (decoded.data.game.skirmish_mode=="expedition")==expedition:return {"ok":true,"preserved":false}
 var digest=HashingContext.new();digest.start(HashingContext.HASH_SHA256)
 if not bytes.is_empty():digest.update(bytes)
 var backup=path+".preserved-"+digest.finish().hex_encode()+".bin"
 if FileAccess.file_exists(backup):
  var existing=FileAccess.open(backup,FileAccess.READ)
  if existing==null:return {"ok":false,"reason":"BACKUP_READ"}
  var same=existing.get_length()==size and existing.get_buffer(size)==bytes;existing.close()
  if not same:return {"ok":false,"reason":"BACKUP_CONFLICT"}
 else:
  var out=FileAccess.open(backup,FileAccess.WRITE)
  if out==null:return {"ok":false,"reason":"BACKUP_WRITE"}
  out.store_buffer(bytes);out.flush();error=out.get_error();out.close()
  if error!=OK:return {"ok":false,"reason":"BACKUP_WRITE"}
  var verify=FileAccess.open(backup,FileAccess.READ)
  if verify==null:return {"ok":false,"reason":"BACKUP_VERIFY"}
  var same=verify.get_length()==size and verify.get_buffer(size)==bytes;verify.close()
  if not same:return {"ok":false,"reason":"BACKUP_VERIFY"}
 return {"ok":true,"preserved":true}
