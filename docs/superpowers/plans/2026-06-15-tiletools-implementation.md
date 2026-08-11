# TileTools Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Pixelorama extension that adds a Tile Select tool for grid-based selection and selection-scoped tiling in tileset workflows.

**Architecture:** Single extension registering a custom tool via `ExtensionsApi.add_tool()`. The tool extends Pixelorama's tool callback pattern (`draw_start`/`draw_move`/`draw_end`) and uses `Global.canvas.selection.select_rect()` for selection operations. Selection-scoped tiling hooks into the drawing pipeline by intercepting draw coordinates and wrapping them within the selection bounding box.

**Tech Stack:** GDScript (Godot 4.x), Pixelorama Extensions API v4

**Reference:** Pixelorama source — `src/Tools/BaseSelectionTool.gd`, `src/Tools/SelectionTools/RectSelect.gd`, `src/Classes/SelectionMap.gd`

---

## File Structure

```
TileTools/
├── extension.json          # Extension metadata (API v4)
├── Main.tscn               # Root scene, instantiated on load
├── Main.gd                 # Entry point: registers/unregisters tool, manages grid overlay
├── TileSelectTool.tscn     # Tool scene required by add_tool()
├── TileSelectTool.gd       # Tool logic: grid math, input handling, selection
├── GridOverlay.gd          # Draws grid lines on the canvas
└── TileTiling.gd           # Selection-scoped tiling: intercepts draw coords, wraps to bounds
```

---

### Task 1: Extension Scaffold

**Files:**
- Create: `TileTools/extension.json`
- Create: `TileTools/Main.tscn`
- Create: `TileTools/Main.gd`

- [ ] **Step 1: Create extension.json**

```json
{
  "name": "TileTools",
  "display_name": "TileTools",
  "description": "Grid-based tile selection and selection-scoped tiling for tileset workflows",
  "author": "AllHailSeizure",
  "version": "0.1",
  "supported_api_versions": [4],
  "license": "MIT",
  "nodes": ["Main.tscn"]
}
```

- [ ] **Step 2: Create Main.tscn**

Create a minimal scene with a Node root named "Main" and attach `Main.gd`.

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://Main.gd" id="1"]

[node name="Main" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 3: Create Main.gd**

```gdscript
extends Node

var extension_api: Node


func _enter_tree() -> void:
	extension_api = get_node_or_null("/root/ExtensionsApi")
	if extension_api == null:
		push_error("TileTools: ExtensionsApi not found")
		return


func _exit_tree() -> void:
	if extension_api == null:
		return
```

- [ ] **Step 4: Verify extension loads in Pixelorama**

1. Open the TileTools project in Godot.
2. Export as PCK: Project > Export > Resources tab > "Export all resources in the project", non-resource filters: `*.json`. Export as `TileTools.pck`.
3. In Pixelorama: Edit > Preferences > Extensions > Add Extension > select `TileTools.pck`.
4. Check Godot console for errors. No `push_error` output means success.

- [ ] **Step 5: Commit**

```bash
git add TileTools/
git commit -m "feat: scaffold TileTools extension with Main entry point"
```

---

### Task 2: Grid Math Utilities

**Files:**
- Create: `TileTools/TileSelectTool.gd` (grid math portion only — tool callbacks come in Task 3)

- [ ] **Step 1: Write grid math functions**

These are pure functions with no dependencies on Pixelorama internals, so they can be tested in isolation in a Godot scene.

```gdscript
extends Node

var grid_size := Vector2i(20, 20)


func pos_to_cell(pos: Vector2i) -> Vector2i:
	var cell_x := pos.x / grid_size.x
	var cell_y := pos.y / grid_size.y
	if pos.x < 0:
		cell_x -= 1
	if pos.y < 0:
		cell_y -= 1
	return Vector2i(cell_x, cell_y)


func cell_to_rect(cell: Vector2i) -> Rect2i:
	return Rect2i(cell * grid_size, grid_size)


func cells_bounding_box(cells: Array[Vector2i]) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var min_cell := cells[0]
	var max_cell := cells[0]
	for cell in cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	return Rect2i(min_cell * grid_size, (max_cell - min_cell + Vector2i.ONE) * grid_size)


func snap_to_grid(pos: Vector2i) -> Vector2i:
	var cell := pos_to_cell(pos)
	return cell * grid_size
```

- [ ] **Step 2: Create a test scene to verify grid math**

Create a temporary test scene (`TestGridMath.gd`) that runs in Godot and prints results:

```gdscript
extends Node

var grid_size := Vector2i(20, 20)


func pos_to_cell(pos: Vector2i) -> Vector2i:
	var cell_x := pos.x / grid_size.x
	var cell_y := pos.y / grid_size.y
	if pos.x < 0:
		cell_x -= 1
	if pos.y < 0:
		cell_y -= 1
	return Vector2i(cell_x, cell_y)


func cell_to_rect(cell: Vector2i) -> Rect2i:
	return Rect2i(cell * grid_size, grid_size)


func _ready() -> void:
	# Cell at origin
	assert(pos_to_cell(Vector2i(0, 0)) == Vector2i(0, 0))
	assert(pos_to_cell(Vector2i(19, 19)) == Vector2i(0, 0))
	# Next cell
	assert(pos_to_cell(Vector2i(20, 0)) == Vector2i(1, 0))
	assert(pos_to_cell(Vector2i(10, 25)) == Vector2i(0, 1))
	# Negative coords
	assert(pos_to_cell(Vector2i(-1, -1)) == Vector2i(-1, -1))
	assert(pos_to_cell(Vector2i(-20, 0)) == Vector2i(-1, 0))
	# Cell to rect
	assert(cell_to_rect(Vector2i(0, 0)) == Rect2i(0, 0, 20, 20))
	assert(cell_to_rect(Vector2i(1, 2)) == Rect2i(20, 40, 20, 20))
	# Snap
	print("All grid math tests passed")
```

Run via: Scene > Run Current Scene. Check output for "All grid math tests passed" and no assertion errors.

- [ ] **Step 3: Remove test scene, commit**

Delete `TestGridMath.gd` and its `.tscn` after verifying.

```bash
git add TileTools/TileSelectTool.gd
git commit -m "feat: add grid math utilities for cell/position conversion"
```

---

### Task 3: Tool Registration and Basic Click Selection

**Files:**
- Create: `TileTools/TileSelectTool.tscn`
- Modify: `TileTools/TileSelectTool.gd` (add tool callbacks)
- Modify: `TileTools/Main.gd` (register/unregister tool)

- [ ] **Step 1: Create TileSelectTool.tscn**

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://TileSelectTool.gd" id="1"]

[node name="TileSelectTool" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: Add tool callback stubs to TileSelectTool.gd**

Add the six required callbacks that `add_tool()` expects. Start with click-to-select-one-cell:

```gdscript
extends Node

var grid_size := Vector2i(20, 20)
var _selected_cells: Array[Vector2i] = []
var _is_drawing := false
var _is_shift_held := false


func pos_to_cell(pos: Vector2i) -> Vector2i:
	var cell_x := pos.x / grid_size.x
	var cell_y := pos.y / grid_size.y
	if pos.x < 0:
		cell_x -= 1
	if pos.y < 0:
		cell_y -= 1
	return Vector2i(cell_x, cell_y)


func cell_to_rect(cell: Vector2i) -> Rect2i:
	return Rect2i(cell * grid_size, grid_size)


func cells_bounding_box(cells: Array[Vector2i]) -> Rect2i:
	if cells.is_empty():
		return Rect2i()
	var min_cell := cells[0]
	var max_cell := cells[0]
	for cell in cells:
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	return Rect2i(min_cell * grid_size, (max_cell - min_cell + Vector2i.ONE) * grid_size)


func snap_to_grid(pos: Vector2i) -> Vector2i:
	var cell := pos_to_cell(pos)
	return cell * grid_size


func draw_start(pos: Vector2i) -> void:
	_is_drawing = true
	_is_shift_held = Input.is_key_pressed(KEY_SHIFT)
	var cell := pos_to_cell(pos)
	if not _is_shift_held:
		_selected_cells.clear()
		_clear_selection()
	if cell not in _selected_cells:
		_selected_cells.append(cell)
	_apply_selection()


func draw_move(pos: Vector2i) -> void:
	if not _is_drawing:
		return
	var cell := pos_to_cell(pos)
	if cell not in _selected_cells:
		_selected_cells.append(cell)
		_apply_selection()


func draw_end(pos: Vector2i) -> void:
	_is_drawing = false


func cursor_move(pos: Vector2i) -> void:
	pass


func draw_indicator(left: bool) -> void:
	pass


func draw_preview() -> void:
	pass


func _apply_selection() -> void:
	var selection := _get_selection_node()
	if selection == null:
		return
	_clear_selection()
	for cell in _selected_cells:
		var rect := cell_to_rect(cell)
		selection.select_rect(rect, 0)  # 0 = add


func _clear_selection() -> void:
	var selection := _get_selection_node()
	if selection == null:
		return
	selection.clear_selection()


func _get_selection_node() -> Node:
	var canvas := get_node_or_null("/root/ExtensionsApi")
	if canvas == null:
		return null
	return canvas.selection.get_canvas().selection if canvas.has_method("get_canvas") else null
```

Note: The exact path to the selection node may need adjustment after testing against the live API. The `select_rect(rect, operation)` call uses operation 0 for add. We may need to use `Global.canvas.selection.select_rect()` directly — this will be verified in Step 4.

- [ ] **Step 3: Register tool in Main.gd**

```gdscript
extends Node

var extension_api: Node
const TOOL_NAME := "TileSelect"


func _enter_tree() -> void:
	extension_api = get_node_or_null("/root/ExtensionsApi")
	if extension_api == null:
		push_error("TileTools: ExtensionsApi not found")
		return
	var tool_scene := preload("res://TileSelectTool.tscn")
	extension_api.add_tool(
		TOOL_NAME,
		"Tile Select",
		tool_scene,
		[],       # layer_types: empty = works on all
		"Grid-based tile selection",
		"",       # shortcut
		[],       # extra_shortcuts
		-1        # insert_point: append at end
	)


func _exit_tree() -> void:
	if extension_api == null:
		return
	extension_api.remove_tool(TOOL_NAME)
```

- [ ] **Step 4: Test in Pixelorama**

1. Export as PCK and load in Pixelorama.
2. Verify "Tile Select" appears in the toolbox.
3. Click on the canvas — verify a 20x20 selection rectangle appears at the grid-aligned position.
4. Click a different cell — verify the previous selection is replaced.
5. If the selection API path is wrong, check Pixelorama console output and adjust `_get_selection_node()`.

- [ ] **Step 5: Commit**

```bash
git add TileTools/
git commit -m "feat: register Tile Select tool with click-to-select-cell"
```

---

### Task 4: Freeform Drag and Shift-Additive Selection

**Files:**
- Modify: `TileTools/TileSelectTool.gd`

- [ ] **Step 1: Implement shift-rectangle mode**

Update `draw_start` and `draw_move` to track shift state and implement rectangle-from-extremities when shift is held during drag:

```gdscript
var _shift_drag_start: Vector2i
var _shift_drag_cells: Array[Vector2i] = []
var _pre_shift_cells: Array[Vector2i] = []


func draw_start(pos: Vector2i) -> void:
	_is_drawing = true
	_is_shift_held = Input.is_key_pressed(KEY_SHIFT)
	_shift_drag_cells.clear()
	var cell := pos_to_cell(pos)
	if _is_shift_held:
		_pre_shift_cells = _selected_cells.duplicate()
		_shift_drag_start = cell
	else:
		_selected_cells.clear()
		_pre_shift_cells.clear()
	if cell not in _selected_cells:
		_selected_cells.append(cell)
	_apply_selection()


func draw_move(pos: Vector2i) -> void:
	if not _is_drawing:
		return
	var cell := pos_to_cell(pos)
	var shift_now := Input.is_key_pressed(KEY_SHIFT)

	if shift_now and not _is_shift_held:
		# Shift just pressed — start rectangle mode from current cell
		_is_shift_held = true
		_pre_shift_cells = _selected_cells.duplicate()
		_shift_drag_start = cell

	if _is_shift_held and shift_now:
		# Rectangle mode: select all cells in rect from _shift_drag_start to current cell
		_shift_drag_cells.clear()
		var min_x := mini(_shift_drag_start.x, cell.x)
		var max_x := maxi(_shift_drag_start.x, cell.x)
		var min_y := mini(_shift_drag_start.y, cell.y)
		var max_y := maxi(_shift_drag_start.y, cell.y)
		for x in range(min_x, max_x + 1):
			for y in range(min_y, max_y + 1):
				_shift_drag_cells.append(Vector2i(x, y))
		# Merge with pre-shift cells
		_selected_cells = _pre_shift_cells.duplicate()
		for c in _shift_drag_cells:
			if c not in _selected_cells:
				_selected_cells.append(c)
		_apply_selection()
	elif not shift_now:
		_is_shift_held = false
		if cell not in _selected_cells:
			_selected_cells.append(cell)
			_apply_selection()


func draw_end(pos: Vector2i) -> void:
	_is_drawing = false
	if _is_shift_held:
		# Commit the shift-rectangle cells into the main selection
		_pre_shift_cells.clear()
		_shift_drag_cells.clear()
	_is_shift_held = false
```

- [ ] **Step 2: Test in Pixelorama**

1. Click and drag — verify freeform cells are selected (every cell the cursor crosses).
2. Click without shift — verify previous selection is cleared.
3. Hold shift and click — verify additive selection.
4. During drag, press shift — verify rectangle mode activates from that point.
5. Release shift mid-drag — verify it reverts to freeform mode.
6. Release mouse, then shift-click a new area — verify it adds to existing selection.

- [ ] **Step 3: Commit**

```bash
git add TileTools/TileSelectTool.gd
git commit -m "feat: add freeform drag and shift-additive rectangle selection"
```

---

### Task 5: Grid Overlay

**Files:**
- Create: `TileTools/GridOverlay.gd`
- Modify: `TileTools/Main.gd` (add/remove overlay)

- [ ] **Step 1: Create GridOverlay.gd**

A Node2D added as a child of the canvas that draws grid lines:

```gdscript
extends Node2D

var grid_size := Vector2i(20, 20)
var grid_color := Color(1.0, 1.0, 1.0, 0.15)


func _draw() -> void:
	var project := _get_current_project()
	if project == null:
		return
	var canvas_size := project.size
	# Vertical lines
	for x in range(0, canvas_size.x + 1, grid_size.x):
		draw_line(Vector2(x, 0), Vector2(x, canvas_size.y), grid_color, 1.0)
	# Horizontal lines
	for y in range(0, canvas_size.y + 1, grid_size.y):
		draw_line(Vector2(0, y), Vector2(canvas_size.x, y), grid_color, 1.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _get_current_project():
	var global := get_node_or_null("/root/Global")
	if global == null:
		return null
	return global.current_project
```

- [ ] **Step 2: Add overlay management to Main.gd**

Add methods to show/hide the grid overlay when the tool is active:

```gdscript
var grid_overlay: Node2D


func show_grid_overlay() -> void:
	if grid_overlay != null:
		return
	grid_overlay = preload("res://GridOverlay.gd").new()
	grid_overlay.name = "TileToolsGridOverlay"
	var canvas := extension_api.general.get_canvas()
	if canvas != null:
		canvas.add_child(grid_overlay)


func hide_grid_overlay() -> void:
	if grid_overlay != null:
		grid_overlay.queue_free()
		grid_overlay = null
```

The overlay should be shown when the Tile Select tool is activated and hidden when switching to another tool. Connect to the appropriate tool-changed signal, or have `TileSelectTool.gd` call these methods via its parent.

- [ ] **Step 3: Create GridOverlay scene file**

Create `TileTools/GridOverlay.tscn` if needed, or instantiate via script (script-only is simpler here since there's no UI).

- [ ] **Step 4: Test in Pixelorama**

1. Select the Tile Select tool — verify grid lines appear on the canvas.
2. Switch to another tool — verify grid lines disappear.
3. Switch back — verify they reappear.
4. Grid lines should be subtle (15% opacity white) and not interfere with drawing.

- [ ] **Step 5: Commit**

```bash
git add TileTools/GridOverlay.gd TileTools/Main.gd
git commit -m "feat: add grid overlay that shows when Tile Select is active"
```

---

### Task 6: Grid-Snapped Move

**Files:**
- Modify: `TileTools/TileSelectTool.gd`

- [ ] **Step 1: Implement grid-snapped move**

When the user clicks on an already-selected area and drags, move the selection content snapped to grid. This integrates with Pixelorama's existing move/transform system by snapping the move delta.

This replaces the `draw_start` from Task 4 (merges move detection with existing shift/freeform logic):

```gdscript
var _is_moving := false
var _move_start_pos: Vector2i


func draw_start(pos: Vector2i) -> void:
	var cell := pos_to_cell(pos)
	_is_shift_held = Input.is_key_pressed(KEY_SHIFT)

	# Check if clicking on an already-selected cell — initiate move
	if cell in _selected_cells and not _is_shift_held:
		_is_moving = true
		_is_drawing = false
		_move_start_pos = snap_to_grid(pos)
		return

	# Otherwise, normal selection behavior (from Task 4)
	_is_drawing = true
	_is_moving = false
	_shift_drag_cells.clear()
	if _is_shift_held:
		_pre_shift_cells = _selected_cells.duplicate()
		_shift_drag_start = cell
	else:
		_selected_cells.clear()
		_pre_shift_cells.clear()
	if cell not in _selected_cells:
		_selected_cells.append(cell)
	_apply_selection()


func draw_move(pos: Vector2i) -> void:
	if _is_moving:
		var snapped_pos := snap_to_grid(pos)
		var delta := snapped_pos - _move_start_pos
		if delta != Vector2i.ZERO:
			var selection := _get_selection_node()
			if selection != null:
				selection.move_content(delta)
			_move_start_pos = snapped_pos
			# Update cell positions
			for i in range(_selected_cells.size()):
				_selected_cells[i] += Vector2i(delta.x / grid_size.x, delta.y / grid_size.y)
		return

	if not _is_drawing:
		return
	# ... existing draw_move logic from Task 4 ...
```

Note: The exact `move_content()` method name may differ — check Pixelorama's `SelectionNode` or use `Global.canvas.selection.move_selection()` from the Extensions API. Adjust during testing.

- [ ] **Step 2: Update draw_end for move**

```gdscript
func draw_end(pos: Vector2i) -> void:
	if _is_moving:
		_is_moving = false
		return
	_is_drawing = false
	if _is_shift_held:
		_pre_shift_cells.clear()
		_shift_drag_cells.clear()
	_is_shift_held = false
```

- [ ] **Step 3: Test in Pixelorama**

1. Select a tile cell with content.
2. Click on the selected cell and drag — verify content moves in grid-sized increments.
3. Verify the selection itself also moves with the content.
4. Verify clicking on an unselected cell still creates a new selection (not a move).

- [ ] **Step 4: Commit**

```bash
git add TileTools/TileSelectTool.gd
git commit -m "feat: add grid-snapped move for selected tiles"
```

---

### Task 7: Tool Settings UI (Grid Size)

**Files:**
- Create: `TileTools/TileSelectSettings.gd`
- Create: `TileTools/TileSelectSettings.tscn`
- Modify: `TileTools/TileSelectTool.gd` (read grid_size from settings)
- Modify: `TileTools/Main.gd` (wire settings to tool)

- [ ] **Step 1: Create TileSelectSettings.tscn**

A simple VBoxContainer with two SpinBoxes for grid width and height:

```gdscript
# TileSelectSettings.gd
extends VBoxContainer

signal grid_size_changed(new_size: Vector2i)

var _width_spinbox: SpinBox
var _height_spinbox: SpinBox


func _ready() -> void:
	var width_label := Label.new()
	width_label.text = "Grid Width:"
	add_child(width_label)

	_width_spinbox = SpinBox.new()
	_width_spinbox.min_value = 1
	_width_spinbox.max_value = 512
	_width_spinbox.value = 20
	_width_spinbox.suffix = "px"
	_width_spinbox.value_changed.connect(_on_size_changed)
	add_child(_width_spinbox)

	var height_label := Label.new()
	height_label.text = "Grid Height:"
	add_child(height_label)

	_height_spinbox = SpinBox.new()
	_height_spinbox.min_value = 1
	_height_spinbox.max_value = 512
	_height_spinbox.value = 20
	_height_spinbox.suffix = "px"
	_height_spinbox.value_changed.connect(_on_size_changed)
	add_child(_height_spinbox)


func _on_size_changed(_value: float) -> void:
	grid_size_changed.emit(Vector2i(int(_width_spinbox.value), int(_height_spinbox.value)))


func get_grid_size() -> Vector2i:
	return Vector2i(int(_width_spinbox.value), int(_height_spinbox.value))
```

- [ ] **Step 2: Wire settings into Main.gd**

Add the settings panel to Pixelorama's tool options area. The exact integration point depends on what `ExtensionsApi` exposes for tool option panels — it may be `extension_api.panel.add_node_as_tab()` or added as a child of the tool options container:

```gdscript
var settings_panel: Node


func _enter_tree() -> void:
	# ... existing code ...
	settings_panel = preload("res://TileSelectSettings.gd").new()
	settings_panel.grid_size_changed.connect(_on_grid_size_changed)
	extension_api.panel.add_node_as_tab(settings_panel, "Tile Settings")


func _exit_tree() -> void:
	# ... existing code ...
	if settings_panel != null:
		extension_api.panel.remove_node_from_tab(settings_panel)
		settings_panel.queue_free()
		settings_panel = null


func _on_grid_size_changed(new_size: Vector2i) -> void:
	# Update tool and overlay
	var tool_node := _get_tool_node()
	if tool_node != null:
		tool_node.grid_size = new_size
	if grid_overlay != null:
		grid_overlay.grid_size = new_size
```

Note: The panel API method names (`add_node_as_tab`, `remove_node_from_tab`) need verification against the live Extensions API. Adjust during testing.

- [ ] **Step 3: Test in Pixelorama**

1. Open the tool settings panel — verify grid width/height spinboxes appear.
2. Change grid size to 32x32 — verify the grid overlay updates.
3. Click to select a cell — verify it uses the new 32x32 size.
4. Change back to 20x20 — verify everything updates.

- [ ] **Step 4: Commit**

```bash
git add TileTools/
git commit -m "feat: add tool settings panel for configurable grid size"
```

---

### Task 8: Selection-Scoped Tiling

**Files:**
- Create: `TileTools/TileTiling.gd`
- Modify: `TileTools/Main.gd` (activate/deactivate tiling)

This is the most complex and uncertain task. The approach depends on how Pixelorama's drawing pipeline can be intercepted.

- [ ] **Step 1: Research the draw pipeline**

Before writing code, inspect how Pixelorama's drawing tools commit pixels. Key questions:
- Does BaseTool provide a hook or signal before pixels are committed?
- Can we override `_get_draw_rect()` from an extension to constrain drawing bounds?
- Is there a pre-draw signal on the canvas or project?

Check these paths in Pixelorama source:
- `src/Tools/BaseTool.gd` — look at `_get_draw_rect()` and how it constrains drawing
- `src/UI/Canvas/Canvas.gd` — look for draw signals
- `src/Autoloads/Global.gd` — look for drawing-related signals

Document findings before proceeding.

- [ ] **Step 2: Implement TileTiling.gd — coordinate wrapping approach**

If direct pipeline interception isn't available, use image manipulation: capture the drawn pixels that fall outside the selection bounding box and wrap them to the opposite side.

```gdscript
extends Node

var _active := false
var _bounds: Rect2i
var _last_image_hash: int


func activate(bounds: Rect2i) -> void:
	_active = true
	_bounds = bounds
	set_process(true)


func deactivate() -> void:
	_active = false
	set_process(false)


func _process(_delta: float) -> void:
	if not _active:
		return
	_wrap_overflow_pixels()


func _wrap_overflow_pixels() -> void:
	# Get current cel image
	var project = get_node_or_null("/root/Global").current_project
	if project == null:
		return
	var cel = project.frames[project.current_frame].cels[project.current_layer]
	if cel == null or not cel.has_method("get_image"):
		return
	var image: Image = cel.get_image()
	if image == null:
		return

	var changed := false
	# Check pixels outside bounds and wrap them
	# This runs each frame while drawing, so it wraps overflow in near-real-time
	for x in range(_bounds.position.x, _bounds.position.x + _bounds.size.x):
		for y in range(_bounds.position.y, _bounds.position.y + _bounds.size.y):
			# For each position in bounds, check if the corresponding
			# overflow positions (one tile-width away in each direction) have pixels
			for dx in [-_bounds.size.x, _bounds.size.x]:
				var src_x := x + dx
				if src_x < 0 or src_x >= image.get_width():
					continue
				var color := image.get_pixel(src_x, y)
				if color.a > 0:
					var existing := image.get_pixel(x, y)
					image.set_pixel(x, y, color)
					image.set_pixel(src_x, y, Color.TRANSPARENT)
					changed = true
			for dy in [-_bounds.size.y, _bounds.size.y]:
				var src_y := y + dy
				if src_y < 0 or src_y >= image.get_height():
					continue
				var color := image.get_pixel(x, src_y)
				if color.a > 0:
					image.set_pixel(x, src_y, Color.TRANSPARENT)
					image.set_pixel(x, y, color)
					changed = true

	if changed:
		cel.update_texture()
```

**Important caveat:** This pixel-wrapping approach is a first attempt. It has performance concerns (iterating all pixels each frame) and may not handle all edge cases (diagonal overflow, brush strokes that span multiple tile widths). It will need iteration based on real-world testing.

**Alternative approach** (if `_get_draw_rect()` can be overridden): Override the draw rectangle to constrain to the selection bounds, and enable Pixelorama's built-in tiling within those bounds. This would be far simpler and more performant but requires source-level access.

- [ ] **Step 3: Wire tiling into Main.gd**

```gdscript
var tile_tiling: Node


func _enter_tree() -> void:
	# ... existing code ...
	tile_tiling = preload("res://TileTiling.gd").new()
	add_child(tile_tiling)


func _exit_tree() -> void:
	# ... existing code ...
	if tile_tiling != null:
		tile_tiling.queue_free()
		tile_tiling = null


func activate_tiling(bounds: Rect2i) -> void:
	if tile_tiling != null:
		tile_tiling.activate(bounds)


func deactivate_tiling() -> void:
	if tile_tiling != null:
		tile_tiling.deactivate()
```

Connect these to the Tile Select tool's selection changes — when a selection exists, activate tiling with its bounding box; when selection is cleared, deactivate.

- [ ] **Step 4: Test in Pixelorama**

1. Select a tile cell with the Tile Select tool.
2. Switch to the pencil tool.
3. Draw a line that goes past the top edge of the selection — verify it appears at the bottom.
4. Draw past the right edge — verify it wraps to the left.
5. Test with a larger selection (multiple cells).
6. Verify performance is acceptable (no visible lag while drawing).

- [ ] **Step 5: Iterate on performance if needed**

If frame-by-frame pixel scanning is too slow:
- Only scan the area immediately outside the bounds (one pixel border)
- Use a signal-based approach if Pixelorama emits draw events
- Limit scanning to only when a draw tool is actively being used

- [ ] **Step 6: Commit**

```bash
git add TileTools/
git commit -m "feat: add selection-scoped tiling with pixel wrapping"
```

---

### Task 9: Integration and Polish

**Files:**
- Modify: `TileTools/Main.gd`
- Modify: `TileTools/TileSelectTool.gd`
- Modify: `TileTools/GridOverlay.gd`

- [ ] **Step 1: Connect tool activation to overlay and tiling**

Ensure the grid overlay shows/hides when the tool is selected/deselected, and tiling activates/deactivates with selection state:

```gdscript
# In Main.gd — connect to tool change signal
func _enter_tree() -> void:
	# ... existing code ...
	# Listen for tool changes to show/hide grid overlay
	var tools_node := get_node_or_null("/root/Tools")
	if tools_node != null and tools_node.has_signal("tool_changed"):
		tools_node.tool_changed.connect(_on_tool_changed)


func _on_tool_changed(tool_name: String) -> void:
	if tool_name == TOOL_NAME:
		show_grid_overlay()
	else:
		hide_grid_overlay()
		deactivate_tiling()
```

Note: The exact signal for tool changes needs verification. It may be on `Tools` singleton or elsewhere.

- [ ] **Step 2: Persist grid size across sessions**

Use `get_config()`/`set_config()` pattern if the tool supports it, or save to a config file:

```gdscript
# In TileSelectTool.gd
func get_config() -> Dictionary:
	return {"grid_width": grid_size.x, "grid_height": grid_size.y}


func set_config(config: Dictionary) -> void:
	grid_size.x = config.get("grid_width", 20)
	grid_size.y = config.get("grid_height", 20)
```

- [ ] **Step 3: Add cell highlight on hover**

Update `cursor_move` and `draw_indicator` to highlight the cell under the cursor:

```gdscript
var _hover_cell: Vector2i


func cursor_move(pos: Vector2i) -> void:
	_hover_cell = pos_to_cell(pos)


func draw_indicator(left: bool) -> void:
	var rect := cell_to_rect(_hover_cell)
	var canvas := get_node_or_null("/root/ExtensionsApi").general.get_canvas()
	if canvas != null:
		canvas.draw_rect(Rect2(rect), Color(1.0, 1.0, 1.0, 0.3), false, 2.0)
```

- [ ] **Step 4: Full integration test**

Test the complete workflow:
1. Open a tileset image (e.g., 160x160 with 20x20 tiles).
2. Select the Tile Select tool — grid overlay appears.
3. Click a tile — it's selected with marching ants.
4. Click and drag across tiles — freeform selection.
5. Shift-click to add tiles — additive selection.
6. Shift-drag — rectangle selection from extremities.
7. Change grid size in settings — overlay and selection behavior update.
8. With a tile selected, switch to pencil and draw past the edge — verify tiling wraps.
9. Click on selected content and drag — verify grid-snapped move.
10. Switch to a different tool — grid overlay disappears, tiling deactivates.
11. Switch back — state is restored.

- [ ] **Step 5: Final commit**

```bash
git add TileTools/
git commit -m "feat: add integration wiring, hover highlight, and config persistence"
```

---

## Known Unknowns (to resolve during implementation)

1. **Selection API path** — `_get_selection_node()` needs to be verified against the live Extensions API. The path may be `extension_api.selection` or require going through `Global.canvas.selection`.
2. **Tool change signal** — need to find the correct signal/method to detect when the user switches tools.
3. **Draw pipeline interception** — the pixel-wrapping approach in Task 8 is a fallback. If Pixelorama's `_get_draw_rect()` or tiling system can be overridden from an extension, that's the better path.
4. **Panel API** — `add_node_as_tab` / `remove_node_from_tab` method names need verification.
5. **Move API** — the exact method for moving selection content grid-snapped needs testing.
