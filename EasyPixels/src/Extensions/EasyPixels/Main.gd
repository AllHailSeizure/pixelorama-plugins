extends Node

var tool_scene := "res://src/Extensions/EasyGradient/GradientTool.tscn"


func _enter_tree() -> void:
	ExtensionsApi.tools.add_tool("GradientLine", "Gradient Line", tool_scene)


func _exit_tree() -> void:
	ExtensionsApi.tools.remove_tool("GradientLine")
