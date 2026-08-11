extends Node

var tool_scene := "res://src/Extensions/TileTools/TileSelectTool.tscn"
var grid_overlay: Node2D
var tile_tiling: Node


func _enter_tree() -> void:
	ExtensionsApi.tools.add_tool("TileSelect", "Tile Select", tool_scene)
	tile_tiling = preload("res://src/Extensions/TileTools/TileTiling.gd").new()
	add_child(tile_tiling)


func _exit_tree() -> void:
	ExtensionsApi.tools.remove_tool("TileSelect")
	if tile_tiling != null:
		tile_tiling.queue_free()
		tile_tiling = null
	hide_grid_overlay()


func show_grid_overlay(grid_size: Vector2i) -> void:
	if grid_overlay != null:
		grid_overlay.grid_size = grid_size
		return
	grid_overlay = preload("res://src/Extensions/TileTools/GridOverlay.gd").new()
	grid_overlay.name = "TileToolsGridOverlay"
	grid_overlay.grid_size = grid_size
	var canvas = ExtensionsApi.general.get_canvas()
	if canvas != null:
		canvas.add_child(grid_overlay)


func hide_grid_overlay() -> void:
	if grid_overlay != null:
		grid_overlay.queue_free()
		grid_overlay = null


func activate_tiling(bounds: Rect2i) -> void:
	if tile_tiling != null:
		tile_tiling.activate(bounds)


func deactivate_tiling() -> void:
	if tile_tiling != null:
		tile_tiling.deactivate()
