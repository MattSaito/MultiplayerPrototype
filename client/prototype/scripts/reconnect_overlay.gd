extends CanvasLayer

# Overlay global da reconexão. Autoload CanvasLayer: aparece sobre qualquer
# cena de gameplay e persiste durante as trocas de cena da reconexão.

var _label: Label

func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var bg: ColorRect = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.6)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	_label = Label.new()
	_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bg.add_child(_label)
	visible = false

func show_message(text: String) -> void:
	_label.text = text
	visible = true

func hide_overlay() -> void:
	visible = false
