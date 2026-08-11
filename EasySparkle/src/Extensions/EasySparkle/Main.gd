extends Node

var tool_scene := "res://src/Extensions/EasySparkle/SparkleTool.tscn"


func _enter_tree() -> void:
	ExtensionsApi.tools.add_tool("EasySparkle", "Easy Sparkle", tool_scene)


func _exit_tree() -> void:
	ExtensionsApi.tools.remove_tool("EasySparkle")
