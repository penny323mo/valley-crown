extends RefCounted
## Presentation only. Inputs must be the player's sanitized faction view.
## A remembered source counts as known even if its hidden stock has changed.
static func missing_resource(worker: Dictionary, records: Dictionary, pending: bool) -> String:
	if pending or not worker.get("owned",false) or not worker.get("alive",false): return ""
	if worker.get("kind","")!="villager" or worker.get("state","")!="idle": return ""
	if worker.get("mode","")!="WORK" or worker.get("path_request_kind","")!="work": return ""
	if worker.get("cargo_milli",0)!=0 or worker.get("path_pending",false): return ""
	if worker.get("path_status","") in ["NO_PATH","LIMIT_REACHED","NO_WORK","QUEUED"]: return ""
	var intent: String=worker.get("gather_type","")
	if intent not in ["food","wood"]: return ""
	for known in records.values():
		if known.get("category","")!="resource" or not known.get("alive",false): continue
		if intent=="food" and known.get("kind","")=="berry": return ""
		if intent=="wood" and known.get("kind","") in ["pine","oak"]: return ""
	return intent

static func label(intent: String) -> String:
	return "無已知糧源" if intent=="food" else ("無已知木源" if intent=="wood" else "")

## Terminal work routes only, from current owned player records. Idle STOP is
## allowed because traffic refusal sets it without erasing the work failure.
## Explicit stop/defend clears the failure and changes request kind to point.
## No route retry, world lookup, or claim about unseen/unreachable map regions.
static func route_failure(worker: Dictionary, pending: bool) -> String:
	if pending or not worker.get("owned",false) or not worker.get("alive",false): return ""
	if worker.get("team",-1)!=0 or worker.get("remembered",false): return ""
	if worker.get("category","")!="unit" or worker.get("kind","")!="villager": return ""
	if worker.get("state","")!="idle" or worker.get("mode","") not in ["WORK","STOP"]: return ""
	if worker.get("path_request_kind","")!="work" or worker.get("path_pending",false): return ""
	if not worker.get("path",[]).is_empty(): return ""
	var status: String=worker.get("path_status","")
	if status not in ["NO_PATH","LIMIT_REACHED","NO_WORK"]: return ""
	var reason: String=worker.get("path_reason","")
	if reason=="work_slots_busy": return "工作位置受阻"
	if reason in ["local_traffic_blocked","local_traffic_timeout","local_traffic_retry_limit","local_traffic_detour_limit"]: return "通道受阻"
	if status=="NO_PATH": return "未找到工作路線"
	if reason in ["expansion_budget_exhausted","retry_rate_limit","candidate_limit","approach_limit"]: return "尋路已達上限"
	return "工作路線已停止"
