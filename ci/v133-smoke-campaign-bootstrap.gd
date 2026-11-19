extends SceneTree
func _initialize():
 if OS.has_feature("web"):JavaScriptBridge.eval("window.vcExternalAudit='stock-release-gdscript';",true)
