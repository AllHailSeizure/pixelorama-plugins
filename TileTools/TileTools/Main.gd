extends Node

var extension_api: Node
var grid_overlay: Node2D
var settings_panel: Node
var tile_tiling: Node
const TOOL_NAME := "TileSelect"


func _enter_tree() -> void:
	extension_api = get_node_or_null("/root/ExtensionsApi")
	if extension_api == null:
		push_error("TileTools: ExtensionsApi not found")
		return
	var tool_scene := preload("res://src/Extensions/TileTools/TileSelectTool.tscn")
	extension_api.add_tool(
		TOOL_NAME,
		"Tile Select",
		tool_scene,
		[],
		"Grid-based tile selection",
		"",
		[],
		-1
	)
	settings_panel = preload("res://src/Extensions/TileTools/TileSelectSettings.gd").new()
	settings_panel.grid_size_changed.connect(_on_grid_size_changed)
	extension_api.panel.add_node_as_tab(settings_panel, "Tile Settings")
	tile_tiling = preload("res://src/Extensions/TileTools/TileTiling.gd").new()
	add_child(tile_tiling)
	# Defer signal connections to next frame so tool node is instantiated
	call_deferred("_connect_tool_signals")


func _exit_tree() -> void:
	if extension_api == null:
		return
	if tile_tiling != null:
		tile_tiling.queue_free()
		tile_tiling = null
	if settings_panel != null:
		extension_api.panel.remove_node_from_tab(settings_panel)
		settings_panel.queue_free()
		settings_panel = null
	extension_api.remove_tool(TOOL_NAME)


func show_grid_overlay() -> void:
	if grid_overlay != null:
		return
	grid_overlay = preload("res://src/Extensions/TileTools/GridOverlay.gd").new()
	grid_overlay.name = "TileToolsGridOverlay"
	var canvas: Variant = extension_api.general.get_canvas()
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


func _connect_tool_signals() -> void:
	var tool_nodes: Array = extension_api.general.get_main_nodes("TileTools")
	if tool_nodes.is_empty():
		return
	for node in tool_nodes:
		var tool_node: Variant = node.get_node_or_null("TileSelectTool")
		if tool_node == null:
			continue
		if tool_node.has_signal("selection_changed"):
			tool_node.selection_changed.connect(_on_selection_changed)
		if tool_node.has_signal("tool_activated"):
			tool_node.tool_activated.connect(show_grid_overlay)
		if tool_node.has_signal("tool_deactivated"):
			tool_node.tool_deactivated.connect(func():
				hide_grid_overlay()
				deactivate_tiling()
			)
		break


func _on_selection_changed(cells: Array[Vector2i]) -> void:
	if cells.is_empty():
		deactivate_tiling()
		return
	# Calculate bounding box and activate tiling
	var tool_nodes: Array = extension_api.general.get_main_nodes("TileTools")
	if tool_nodes.is_empty():
		return
	for node in tool_nodes:
		var tool_node: Variant = node.get_node_or_null("TileSelectTool")
		if tool_node == null:
			continue
		var bounds: Rect2i = tool_node.cells_bounding_box(cells)
		activate_tiling(bounds)
		break


func _on_grid_size_changed(new_size: Vector2i) -> void:
	if grid_overlay != null:
		grid_overlay.grid_size = new_size
	# Update tool's grid size
	var tool_nodes: Array = extension_api.general.get_main_nodes("TileTools")
	if not tool_nodes.is_empty():
		for node in tool_nodes:
			var tool_node: Variant = node.get_node_or_null("TileSelectTool")
			if tool_node != null:
				tool_node.grid_size = new_size
				break
