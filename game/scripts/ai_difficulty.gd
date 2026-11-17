extends RefCounted
## Only offensive timing/cohort limits; no combat, economy or vision privilege.
const Skirmish=preload("res://scripts/skirmish_policy.gd")
const EASY_INTERVAL=3600
const EASY_FIRST_RAID=3600
const EASY_BATCH=5
static func supported(mode:String,victory:String)->bool:return mode=="standard" and victory=="conquest"
static func valid_for(mode:String,victory:String,value:String)->String:return "easy" if supported(mode,victory) and value=="easy" else "standard"
static func easy(mode:String,victory:String,value:String)->bool:return valid_for(mode,victory,value)=="easy"
static func interval(mode:String,victory:String,value:String)->int:return EASY_INTERVAL if easy(mode,victory,value) else Skirmish.interval(mode)
static func initial_ready(mode:String,victory:String,value:String,tick:int)->bool:return not easy(mode,victory,value) or tick>=EASY_FIRST_RAID
static func limit(ids:Array,mode:String,victory:String,value:String)->Array:return ids.slice(0,EASY_BATCH) if easy(mode,victory,value) else ids.duplicate()
static func title(value:String)->String:return "較低襲擊壓力" if value=="easy" else "標準"
static func details(value:String)->String:
 if value=="easy":return "最早 180 秒出征；出征或增援至少相隔 180 秒，每批最多 5 兵。守城、採集照常；傷害、資源、速度、視野無加成。"
 return "原有規則：至少 5 兵集結後出征；出征或增援至少相隔 90 秒，批量不變。"
