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
