extends SceneTree
## 无窗口流程回放，不是玩家可操控界面；用于复现实验和验证正式系统。
const Routes=preload("res://scenarios/wet_ruins_routes.gd")
func _initialize() -> void:
	for route in ["manual","drainage","authored"]:
		var result: Dictionary=Routes.run(route)
		if not result.ok:
			printerr(route," failed: ",result.error)
			quit(1)
			return
		result.erase("checkpoint")
		print(JSON.stringify(result))
	quit(0)
