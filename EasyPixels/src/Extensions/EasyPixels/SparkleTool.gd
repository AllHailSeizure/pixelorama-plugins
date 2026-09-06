extends Node

const SparklePalette = preload(
	"res://src/Extensions/EasySparkle/SparklePalette.gd"
)
const SparkleRegionFinder = preload(
	"res://src/Extensions/EasySparkle/SparkleRegion.gd"
)
const SparkleFill = preload(
	"res://src/Extensions/EasySparkle/SparkleFill.gd"
)
const SparkleQuota = preload(
	"res://src/Extensions/EasySparkle/SparkleQuota.gd"
)

# Seeds are kept in this range purely so the visible spin box shows a short,
# easy-to-compare/retype number; SparkleFill accepts any int seed.
const _SEED_MAX := 999999

# Pixelorama tool interface (see src/Tools/BaseTool.gd)
var is_moving := false
var is_syncing := false
var kname: String
var tool_slot = null
var cursor_text := ""

var _region_label: Label
var _canvas: Node2D
var _hover := Vector2i.ZERO

# One labeled swatch per SparklePalette role, in SparklePalette.ROLE_ORDER.
var _palette_swatches: Array[ColorRect] = []

# The region targeted by the most recent click, previewed via its outline
# while also being the region the click's sparkle fill was (or would be)
# applied to.
var _region_points: Array[Vector2i] = []
var _region_color := Color.TRANSPARENT
var _has_region := false

# The seed driving sparkle placement (see SparkleFill). Visible and editable
# via _seed_spin, and persisted like any other tool option.
var _current_seed := 0
var _seed_spin: SpinBox
var _reroll_button: Button


func _ready() -> void:
	kname = name.replace(" ", "_").to_lower()
	if tool_slot != null:
		if tool_slot.name == "Left tool":
			$ColorRect.color = ExtensionsApi.general.get_global().left_tool_color
		else:
			$ColorRect.color = ExtensionsApi.general.get_global().right_tool_color

	var preview_label := Label.new()
	preview_label.text = "Sparkle palette preview (hovered pixel)"
	preview_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(preview_label)

	var palette_row := HBoxContainer.new()
	palette_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(palette_row)
	for role in SparklePalette.ROLE_ORDER:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		palette_row.add_child(column)
		_palette_swatches.append(_make_swatch(column))
		var caption := Label.new()
		caption.text = SparklePalette.role_name(role)
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(caption)

	_region_label = Label.new()
	_region_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_region_label)

	var seed_row := HBoxContainer.new()
	seed_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(seed_row)
	var seed_label := Label.new()
	seed_label.text = "Seed"
	seed_row.add_child(seed_label)
	_seed_spin = SpinBox.new()
	_seed_spin.min_value = 0
	_seed_spin.max_value = _SEED_MAX
	_seed_spin.step = 1
	_seed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_spin.value_changed.connect(_on_seed_changed)
	seed_row.add_child(_seed_spin)

	_reroll_button = Button.new()
	_reroll_button.text = "Reroll"
	_reroll_button.pressed.connect(_on_reroll_pressed)
	add_child(_reroll_button)

	var hint := Label.new()
	hint.text = "Click a non-transparent pixel to sparkle-fill its connected, exact-color region. Reroll (or edit the seed) to try a different arrangement on the same region."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)

	_canvas = ExtensionsApi.general.get_canvas()
	load_config()
	_update_palette_preview()
	_update_region_status()


func _make_swatch(parent: Control) -> ColorRect:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(0, 18)
	swatch.color = Color.TRANSPARENT
	panel.add_child(swatch)
	return swatch


func save_config() -> void:
	if tool_slot == null:
		return
	ExtensionsApi.general.get_config_file().set_value(tool_slot.kname, kname, get_config())


func load_config() -> void:
	if tool_slot == null:
		return
	var value = ExtensionsApi.general.get_config_file().get_value(tool_slot.kname, kname, {})
	set_config(value)
	update_config()


func get_config() -> Dictionary:
	# The palette is derived on the fly from SparklePalette; the seed is the
	# one setting worth persisting per tool slot, same as any other option.
	return {"seed": _current_seed}


func set_config(config: Dictionary) -> void:
	_current_seed = int(config.get("seed", randi() % (_SEED_MAX + 1)))
	if _seed_spin != null:
		_seed_spin.set_value_no_signal(_current_seed)


func update_config() -> void:
	_update_palette_preview()


## A click targets the connected, exact-color region under the cursor and,
## in the same click, applies the structured sparkle fill to it using the
## currently visible seed. Unsupported cels, transparent pixels, and
## out-of-bounds clicks are all no-ops that simply clear the preview --
## nothing is written to the image in those cases. A successful fill is
## recorded as a single undoable/redoable action.
func draw_start(pos: Vector2i) -> void:
	var project = ExtensionsApi.project.current_project
	if project == null:
		_clear_region()
		return
	var cel = ExtensionsApi.project.get_current_cel()
	if not cel is PixelCel:
		_clear_region()
		return
	var image: Image = cel.get_image()
	var result := SparkleRegionFinder.find_region(image, pos)
	if result.is_empty():
		_clear_region()
		return
	_region_points = result["points"]
	_region_color = result["color"]
	_has_region = true

	_apply_fill(project, cel, image, "Sparkle Fill")
	_update_region_status()


func draw_move(_pos: Vector2i) -> void:
	pass


func draw_end(_pos: Vector2i) -> void:
	pass


func cancel_tool() -> void:
	_clear_region()


func cursor_move(pos: Vector2i) -> void:
	_hover = pos
	_update_palette_preview()


## Fired by typing a new value into the seed spin box. If a region is
## already targeted, immediately regenerates its fill with the new seed --
## the same seed value always reproduces the same arrangement for that
## region, so retyping a previous seed reproduces a previous arrangement.
func _on_seed_changed(value: float) -> void:
	_current_seed = int(value)
	if not _has_region:
		return
	var project = ExtensionsApi.project.current_project
	if project == null:
		return
	var cel = ExtensionsApi.project.get_current_cel()
	if not cel is PixelCel:
		return
	_apply_fill(project, cel, cel.get_image(), "Sparkle Reroll")
	_update_region_status()


## Picks a new seed and regenerates the current region's fill with it --
## the same one-step action a user could get by typing a new seed value.
## No-op with no active region, since there is nothing to reroll yet.
func _on_reroll_pressed() -> void:
	if not _has_region or _seed_spin == null:
		return
	var new_seed := _current_seed
	while new_seed == _current_seed:
		new_seed = randi() % (_SEED_MAX + 1)
	# Triggers _on_seed_changed, which does the actual reapply.
	_seed_spin.value = new_seed


## Applies the sparkle fill for the currently targeted region
## (`_region_points`/`_region_color`) to `image` using `_current_seed`, as
## one undoable/redoable action named `action_name`. Placement is
## regenerated purely from the stored source region, palette, and quotas --
## never from whatever is currently painted on `image` -- so this is safe
## to call repeatedly (e.g. on every reroll or seed edit) without
## compounding on top of a previous fill.
func _apply_fill(project, cel: BaseCel, image: Image, action_name: String) -> void:
	var region := {"points": _region_points, "color": _region_color}

	var cels: Array[BaseCel] = [cel]
	var undo_data := {}
	project.serialize_cel_undo_data(cels, undo_data)

	SparkleFill.apply(image, region, SparkleQuota.DEFAULT_PROFILE, _current_seed)

	_commit_undo(project, cels, undo_data, action_name)


func draw_indicator(left: bool) -> void:
	if _canvas == null:
		return

	if _has_region:
		var global = ExtensionsApi.general.get_global()
		var region_color: Color = global.left_tool_color if left else global.right_tool_color
		region_color.a = 0.35
		for point in _region_points:
			_canvas.indicators.draw_rect(Rect2(Vector2(point), Vector2.ONE), region_color, true)


func draw_preview() -> void:
	pass


## Refreshes the tool-options palette preview swatches from the pixel
## currently under the cursor. Every role in SparklePalette.ROLE_ORDER gets
## its own swatch, so the full six-role palette is always visible together,
## not just whichever role a user happens to pick. This never reads or
## writes anything but the swatch colors themselves -- no image is touched.
func _update_palette_preview() -> void:
	if _palette_swatches.is_empty():
		return
	var image := _current_image()
	var valid := image != null and _in_bounds(image, _hover)
	if not valid:
		for swatch in _palette_swatches:
			swatch.color = Color.TRANSPARENT
		return
	var source := image.get_pixelv(_hover)
	var palette := SparklePalette.build(source)
	for i in SparklePalette.ROLE_ORDER.size():
		var role = SparklePalette.ROLE_ORDER[i]
		_palette_swatches[i].color = palette[role]


func _update_region_status() -> void:
	if _region_label == null:
		return
	if _has_region:
		var count := _region_points.size()
		_region_label.text = "Region: %d pixel%s selected." % [count, "" if count == 1 else "s"]
	else:
		_region_label.text = "No region selected."


## Registers the completed fill as one undoable/redoable action, the same
## way EasyGradient's fill does: snapshot before (`undo_data`) and after
## (`redo_data`) the write, then hand both to the project's UndoRedo. Each
## call -- whether from the initial click, a reroll, or a seed edit --
## creates its own separate, predictable undo step; none of them merge or
## replace a previous step's undo data.
func _commit_undo(project, cels: Array[BaseCel], undo_data: Dictionary, action_name: String = "Sparkle Fill") -> void:
	var global = ExtensionsApi.general.get_global()
	global.canvas.update_selected_cels_textures(project)
	var redo_data := {}
	project.serialize_cel_undo_data(cels, redo_data)
	project.undo_redo.create_action(action_name)
	project.deserialize_cel_undo_data(redo_data, undo_data)
	project.undo_redo.add_do_method(global.undo_or_redo.bind(false, project.current_frame, project.current_layer))
	project.undo_redo.add_undo_method(global.undo_or_redo.bind(true, project.current_frame, project.current_layer))
	project.undo_redo.commit_action()


func _clear_region() -> void:
	_region_points = []
	_region_color = Color.TRANSPARENT
	_has_region = false
	_update_region_status()


func _current_image() -> Image:
	var cel = ExtensionsApi.project.get_current_cel()
	if not cel is PixelCel:
		return null
	return cel.get_image()


func _in_bounds(image: Image, point: Vector2i) -> bool:
	return (
		point.x >= 0
		and point.y >= 0
		and point.x < image.get_width()
		and point.y < image.get_height()
	)
