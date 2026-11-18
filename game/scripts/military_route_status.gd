extends RefCounted
## Read-only current own observations. A terminal result is not proof of an
## unseen obstacle; never inspect targets, enemy records or authoritative paths.
const KINDS=["scout","spearman","archer","cavalry","siege"]
static func failure(record: Dictionary,pending=false) -> String:
 if pending or not record.get("owned",false) or not record.get("alive",false) or record.get("remembered",false) or record.get("team",-1)!=0:return ""
 if record.get("category","")!="unit" or record.get("kind","") not in KINDS:return ""
 if record.get("combat_engaged",false):return ""
 if record.get("path_pending",false) or not record.get("path",[]).is_empty():return ""
 if record.get("path_status","") not in ["NO_PATH","LIMIT_REACHED"]:return ""
 if record.get("path_reason","") in ["local_traffic_blocked","local_traffic_timeout","local_traffic_retry_limit","local_traffic_detour_limit"]:return "通道受阻，已停止"
 if record.get("path_status","")=="LIMIT_REACHED":return "尋路已達上限，已停止"
 return "未找到路線，已停止"
static func blocked(records: Dictionary,selected: Array,pending=false) -> Array:
 var ids=[]
 for id in selected:
  if id not in ids and not failure(records.get(id,{}),pending).is_empty():ids.append(id)
 ids.sort();return ids
