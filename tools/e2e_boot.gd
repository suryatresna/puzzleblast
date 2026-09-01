extends Node
## Spawns the probe as a sibling of the current scene, so navigating away does
## not take the test with it.
func _ready() -> void:
	var probe: Node = load("res://tools/e2e.gd").new()
	probe.name = "Probe"
	get_tree().root.call_deferred("add_child", probe)
