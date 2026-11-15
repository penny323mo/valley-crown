extends RefCounted
## Local display-only completed reports. Never loads world state or grants rewards.
const Report=preload("res://scripts/match_report.gd")
const PATH="user://battle_history_v1.json"
const LIMIT=10
const MAX_BYTES=1048576
const PAGES=["overview","economy","units","buildings"]

static func read_history(path: String=PATH) -> Dictionary:
	if not FileAccess.file_exists(path):return {"ok":true,"entries":[]}
	var file=FileAccess.open(path,FileAccess.READ)
	if file==null:return {"ok":false,"entries":[],"reason":"無法讀取本機戰績"}
	if file.get_length()>MAX_BYTES:return {"ok":false,"entries":[],"reason":"戰績檔案過大，未改動原檔"}
	var parser=JSON.new()
	var error=parser.parse(file.get_as_text());file.close()
	if error!=OK or typeof(parser.data)!=TYPE_DICTIONARY:return {"ok":false,"entries":[],"reason":"戰績資料損壞，未改動原檔"}
	var data=parser.data
	if data.get("version",0)!=1 or typeof(data.get("entries"))!=TYPE_ARRAY or data.entries.size()>LIMIT:return {"ok":false,"entries":[],"reason":"戰績格式不相容，未改動原檔"}
	var seen={}
	for entry in data.entries:
		if not _valid_entry(entry) or seen.has(entry.id):return {"ok":false,"entries":[],"reason":"戰績資料無效，未改動原檔"}
		seen[entry.id]=true
	return {"ok":true,"entries":data.entries.duplicate(true)}

static func _valid_entry(entry) -> bool:
	if typeof(entry)!=TYPE_DICTIONARY:return false
	for key in ["id","saved_at","outcome","build"]:
		if typeof(entry.get(key))!=TYPE_STRING or entry[key].length()>160:return false
	if entry.id.is_empty() or entry.outcome not in ["victory","defeat","draw"] or typeof(entry.get("pages"))!=TYPE_DICTIONARY:return false
	for page in PAGES:
		if typeof(entry.pages.get(page))!=TYPE_STRING or entry.pages[page].length()>16000:return false
	return true

static func append_report(report: Dictionary, id: String, path: String=PATH) -> Dictionary:
	var current=read_history(path)
	if not current.ok:return current
	if id.is_empty() or id.length()>160 or report.get("outcome","") not in ["victory","defeat","draw"]:return {"ok":false,"reason":"無效戰役，未儲存"}
	for old in current.entries:
		if old.id==id:return {"ok":true,"duplicate":true}
	var entry={"id":id,"saved_at":Time.get_datetime_string_from_system(false,true),"outcome":report.outcome,"build":report.get("build",""),"pages":{}}
	for page in PAGES:entry.pages[page]=Report.page_text(report,page)
	if not _valid_entry(entry):return {"ok":false,"reason":"戰績內容過長，未儲存"}
	current.entries.push_front(entry)
	if current.entries.size()>LIMIT:current.entries.resize(LIMIT)
	var text=JSON.stringify({"version":1,"entries":current.entries})
	if text.to_utf8_buffer().size()>MAX_BYTES:return {"ok":false,"reason":"戰績內容過大，未儲存"}
	var temp=path+".tmp"
	var file=FileAccess.open(temp,FileAccess.WRITE)
	if file==null:return {"ok":false,"reason":"本機儲存不可用"}
	file.store_string(text);file.flush();var error=file.get_error();file.close()
	if error!=OK:return {"ok":false,"reason":"本機寫入失敗"}
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temp),ProjectSettings.globalize_path(path))!=OK:return {"ok":false,"reason":"本機戰績儲存失敗"}
	return {"ok":true,"duplicate":false}
