extends "res://tests/test_ascent_route.gd"
func _initialize()->void:
	route_with_stone=true
	call_deferred("_run")
func finish()->void:
	print("ASCENT_STONE_TEST_RESULT: ",passed," passed; ",failed," failed");quit(0 if failed==0 else 1)
