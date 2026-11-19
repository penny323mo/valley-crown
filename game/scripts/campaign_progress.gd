extends RefCounted
## Device-local chapter completion only. Not a live game checkpoint.
const PATH="user://valley_campaign_progress_v1.json"
const WEB_KEY="penny323mo.valley-crown.campaign-progress.v1"
const SCHEMA=1
const MAX_BYTES=192
const MAX_REVISION=2147483647
# Only this scoped local storage key can be touched. Fetch/read before compare
# and save, capture errors, and return the exact saved bytes as acknowledgement.
const WEB_FUNCTION="""(function(k,action,expected,target){
try {
  var db=window.localStorage, old=db.getItem(k);
  if(old!==null&&old.length>192)return JSON.stringify({ok:false,reason:"INVALID"});
  if(action==="read")return JSON.stringify({ok:true,raw:old});
  if(action!=="write"||old!==expected)return JSON.stringify({ok:false,reason:"CONFLICT"});
  db.setItem(k,target);
  var actual=db.getItem(k);
  return actual===target?JSON.stringify({ok:true,raw:actual}):JSON.stringify({ok:false,reason:"READBACK"});
} catch (_) { return JSON.stringify({ok:false,reason:"UNAVAILABLE"}); }
})"""

static func error(reason:String)->Dictionary:
 return {"ok":false,"reason":reason}

static func _decode(raw)->Dictionary:
 if raw==null:return {"ok":true,"raw":null,"revision":0,"completed":0}
 if not raw is String or raw.to_utf8_buffer().size()>MAX_BYTES:return error("INVALID")
 var parser=JSON.new()
 if parser.parse(raw)!=OK:return error("INVALID")
 var data=parser.data
 if not data is Dictionary or data.size()!=3 or not data.has_all(["schema","revision","completed"]):return error("INVALID")
 if not _whole(data.schema) or data.schema!=SCHEMA or not _whole(data.revision) or not _whole(data.completed):return error("INVALID")
 if data.completed<0 or data.completed>3 or data.revision<data.completed or data.revision>MAX_REVISION:return error("INVALID")
 return {"ok":true,"raw":raw,"revision":int(data.revision),"completed":int(data.completed)}

static func _whole(value)->bool:
 return (value is int or value is float) and is_finite(float(value)) and float(value)==floorf(float(value))

static func _native_read(path:String)->Dictionary:
 if not FileAccess.file_exists(path):return _decode(null)
 var reader=FileAccess.open(path,FileAccess.READ)
 if reader==null:return error("UNAVAILABLE")
 var valid_length=reader.get_length()<=MAX_BYTES
 var raw=reader.get_as_text() if valid_length else ""
 reader.close()
 return _decode(raw)

static func _browser_call(action:String,expected=null,target=null)->Dictionary:
 var result=JavaScriptBridge.eval(WEB_FUNCTION+"("+JSON.stringify(WEB_KEY)+","+JSON.stringify(action)+","+JSON.stringify(expected)+","+JSON.stringify(target)+")",true)
 if not result is String or result.length()>MAX_BYTES*4:return error("UNAVAILABLE")
 var parser=JSON.new()
 if parser.parse(result)!=OK:return error("UNAVAILABLE")
 var reply=parser.data
 if not reply is Dictionary or not reply.get("ok",false):return error(str(reply.get("reason","UNAVAILABLE")) if reply is Dictionary else "UNAVAILABLE")
 return _decode(reply.get("raw",null)) if reply.has("raw") else error("READBACK")

static func read(path:String=PATH)->Dictionary:
 return _browser_call("read") if OS.has_feature("web") else _native_read(path)

static func save(expected:Dictionary,completed:int,reset:bool=false,path:String=PATH)->Dictionary:
 if not expected.get("ok",false) or not expected.has("raw"):return error("UNAVAILABLE")
 var old=_decode(expected.raw)
 if not old.ok or old.revision!=expected.get("revision",-1) or old.completed!=expected.get("completed",-1):return error("INVALID")
 if old.revision>=MAX_REVISION or completed<0 or completed>3:return error("INVALID")
 if reset:
  if completed!=0 or old.completed==0:return error("INVALID")
 elif completed!=old.completed+1:return error("INVALID")
 var encoded=JSON.stringify({"schema":SCHEMA,"revision":old.revision+1,"completed":completed})
 if OS.has_feature("web"):return _browser_call("write",old.raw,encoded)
 var now=_native_read(path)
 if not now.ok:return now
 if now.raw!=old.raw:return error("CONFLICT")
 var temp=path+".writing"
 var writer=FileAccess.open(temp,FileAccess.WRITE)
 if writer==null:return error("UNAVAILABLE")
 writer.store_string(encoded);writer.flush()
 var ok=writer.get_error()==OK
 writer.close()
 if not ok:return error("WRITE")
 var verified=_native_read(temp)
 if not verified.ok or verified.raw!=encoded:return error("READBACK")
 # Check again after temp file I/O; do not intentionally overwrite a
 # known newer record. Dedicated nonbrowser file never aliases old save slots.
 now=_native_read(path)
 if not now.ok or now.raw!=old.raw:return error("CONFLICT")
 var rename=DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path))
 if rename!=OK:return error("WRITE")
 verified=_native_read(path)
 return verified if verified.ok and verified.raw==encoded else error("READBACK")
