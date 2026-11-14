extends RefCounted
## Presentation only. Read the player's sanitized faction records, never authority.
static func detail(site: Dictionary, records: Dictionary, pending=false, paused=false) -> String:
	if not site.get("owned",false) or not site.get("alive",false) or site.get("remembered",false): return ""
	if site.get("team",-1)!=0 or site.get("category","")!="building" or site.get("built",true): return ""
	var prefix="施工 %d%% · " % clampi(int(site.get("progress",0.0)*100),0,100)
	if paused: return prefix+"已暫停；按繼續返回戰場"
	# Do not display the old assignment as the outcome of a queued own command.
	if pending: return prefix+"指令等待中"
	var assigned=false
	var walking=false
	var searching=false
	var stopped=false
	for worker in records.values():
		if not worker.get("owned",false) or not worker.get("alive",false) or worker.get("remembered",false): continue
		if worker.get("team",-1)!=0 or worker.get("category","")!="unit" or worker.get("kind","")!="villager": continue
		if worker.get("state","")!="build" or worker.get("target",-1)!=site.get("id",-2): continue
		assigned=true
		# This cue is published only after a successful construction work tick.
		# An assigned order or an empty path alone is not evidence of building.
		if worker.get("visual_action","")=="build": return prefix+"建造中"
		searching=searching or worker.get("path_pending",false)
		walking=walking or not worker.get("path",[]).is_empty()
		stopped=stopped or worker.get("path_status","") in ["NO_PATH","LIMIT_REACHED","NO_WORK"]
	if walking: return prefix+"村民移動到工地"
	if searching: return prefix+"村民已接單，尋路中"
	if stopped: return prefix+"村民尋路停止；選村民後直接點工地"
	if assigned: return prefix+"村民已接單，等候施工"
	return prefix+"無施工村民；可按「派閒置村民續建」"
