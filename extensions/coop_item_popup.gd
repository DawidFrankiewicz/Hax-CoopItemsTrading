extends "res://ui/menus/shop/coop_item_popup.gd"

const TRADE_PATH: = "res://mods-unpacked/Hax-CoopItemsTrading/extensions/trade.gd"
const GOLD_ICON: = preload("res://items/materials/material_ui.png")

var _give_button: Button
var _player_button: Button
var _give_text: Label
var _give_spacer: Control
var _give_cost: Label
var _give_icon: TextureRect
var _target_player_index: = -1


func _trade():
	return load(TRADE_PATH)


func _ready() -> void:
	_ensure_give_controls()


func should_show_buttons(item_data: ItemParentData, focused: bool) -> bool:
	if _in_shop() and RunData.is_coop_run and focused and buttons_enabled and _trade().can_give(item_data, player_index) and not _trade().other_players(player_index).empty():
		return true

	return .should_show_buttons(item_data, focused)


func _update_button_visibilities() -> void:
	_ensure_give_controls()

	if _item_data is ItemData and not _item_data is CharacterData:
		_show_item_action_buttons()
	else:
		._update_button_visibilities()

	_refresh_give_controls()


func _on_UpgradeButton_pressed() -> void:
	._on_UpgradeButton_pressed()

	if _pending_upgrade != null:
		_hide_give_controls()


func _ensure_give_controls() -> void:
	if _give_button != null or _cancel_button == null:
		return

	var box: Node = _cancel_button.get_parent()
	_player_button = _make_button("GivePlayerButton")
	_give_button = _make_button("GiveButton")
	box.add_child_below_node(_discard_button, _player_button)
	box.add_child_below_node(_player_button, _give_button)
	_player_button.connect("pressed", self, "_on_player_button_pressed")
	_give_button.connect("pressed", self, "_on_give_button_pressed")
	_make_give_value_display(_give_button)
	_hide_give_controls()


func _make_button(button_name: String) -> Button:
	# A plain Button, not MyMenuButton. That script disables itself on press and
	# drops focus, which would close this popup when the trade is refused.
	var button: = Button.new()
	button.name = button_name
	button.theme = _cancel_button.theme
	button.add_font_override("font", _cancel_button.get_font("font"))
	button.focus_mode = FOCUS_NONE
	button.size_flags_horizontal = _cancel_button.size_flags_horizontal
	button.size_flags_vertical = _cancel_button.size_flags_vertical
	button.connect("focus_entered", self, "_on_give_control_focused")
	button.hide()
	return button


func _on_give_control_focused() -> void:
	SoundManager.play(load("res://ui/sounds/button_focus.wav"), 0, 0.2)


func _make_give_value_display(button: Button) -> void:
	var box: = HBoxContainer.new()
	box.name = "GiveValueDisplay"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGN_CENTER
	box.add_constant_override("separation", 6)
	box.set_anchors_and_margins_preset(Control.PRESET_WIDE)
	button.add_child(box)

	_give_text = _make_give_label("COOP_TRADE_GIVE")
	box.add_child(_give_text)

	_give_spacer = Control.new()
	_give_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_give_spacer.rect_min_size = Vector2(12, 0)
	box.add_child(_give_spacer)

	_give_cost = _make_give_label("")
	box.add_child(_give_cost)

	_give_icon = TextureRect.new()
	_give_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_give_icon.texture = GOLD_ICON
	_give_icon.expand = true
	_give_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_give_icon.modulate = Utils.GOLD_COLOR
	_give_icon.size_flags_vertical = SIZE_SHRINK_CENTER
	box.add_child(_give_icon)


func _make_give_label(label_text: String) -> Label:
	var label: = Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.size_flags_vertical = SIZE_EXPAND_FILL
	label.text = label_text
	return label


func _process(_delta: float) -> void:
	if _give_button != null and _give_button.visible:
		_update_give_font_color()


func _show_item_action_buttons() -> void:
	_cancel_pending_upgrade()

	var buttons: = [_combine_button, _discard_button, _cancel_button]
	if _upgrade_button != null:
		buttons.append(_upgrade_button)

	for button in buttons:
		button.hide()
		button.focus_mode = FOCUS_NONE

	if _item_data != null and should_show_buttons(_item_data, _focused):
		_cancel_button.show()
		_cancel_button.focus_mode = FOCUS_ALL if _focused else FOCUS_NONE


func _refresh_give_controls() -> void:
	if _give_button == null:
		return

	if _pending_upgrade != null or not _focused or not _is_inventory_element or not _in_shop() or not _trade().can_give(_item_data, player_index):
		_hide_give_controls()
		return

	var others: Array = _trade().other_players(player_index)
	if others.empty():
		_hide_give_controls()
		return

	if not others.has(_target_player_index):
		_target_player_index = others[0]

	var cost: int = _trade().give_cost(_item_data, player_index)
	var show_cost: bool = cost > 0
	var can_pay: bool = not show_cost or RunData.get_player_currency(player_index) >= cost
	var can_receive: bool = _trade().can_receive(_item_data, _target_player_index)
	var show_player_choice: bool = others.size() > 1

	_player_button.visible = show_player_choice
	_player_button.focus_mode = FOCUS_ALL if show_player_choice else FOCUS_NONE
	_player_button.text = Text.text("COOP_PLAYER", [str(_target_player_index + 1)])
	_set_font_color(_player_button, CoopService.get_player_color(_target_player_index))

	_give_button.show()
	_give_button.focus_mode = FOCUS_ALL
	_give_button.text = ""
	_give_text.text = "COOP_TRADE_GIVE"
	_give_spacer.visible = show_cost
	_give_cost.visible = show_cost
	_give_icon.visible = show_cost
	_give_cost.text = "-" + str(cost)
	var font: Font = _give_button.get_font("font")
	_give_text.add_font_override("font", font)
	_give_cost.add_font_override("font", font)
	_give_icon.rect_min_size = Vector2(font.get_height(), font.get_height())
	if can_pay and can_receive:
		_clear_font_color(_give_button)
	else:
		_set_font_color(_give_button, Color(ProgressData.settings.color_negative))
	_update_give_font_color()

	_link_visible_buttons()


func _hide_give_controls() -> void:
	if _give_button != null:
		_give_button.hide()
		_give_button.focus_mode = FOCUS_NONE
	if _player_button != null:
		_player_button.hide()
		_player_button.focus_mode = FOCUS_NONE


func _on_player_button_pressed() -> void:
	var others: Array = _trade().other_players(player_index)
	if others.size() < 2:
		return

	var index: int = others.find(_target_player_index)
	_target_player_index = others[(index + 1) % others.size()]
	_refresh_give_controls()

	if _player_button.visible:
		_player_button.grab_focus()


func _on_give_button_pressed() -> void:
	if _item_data == null or _target_player_index < 0:
		return

	var cost: int = _trade().give_cost(_item_data, player_index)
	if (cost > 0 and RunData.get_player_currency(player_index) < cost) or not _trade().can_receive(_item_data, _target_player_index):
		if cost > 0 and RunData.get_player_currency(player_index) < cost:
			var shop = _find_shop()
			if shop != null:
				shop.shake_player_currency(player_index)
		return

	var shop = _find_shop()
	if shop == null:
		return

	shop.give_item_to_player(_item_data, player_index, _target_player_index)


func _in_shop() -> bool:
	return _find_shop() != null


func _find_shop() -> Node:
	var node = get_parent()
	while node != null:
		if node.has_method("give_item_to_player") and node.has_method("buy_item"):
			return node
		node = node.get_parent()
	return null


func _link_visible_buttons() -> void:
	var buttons: Array = []
	for button in [_combine_button, _discard_button, _player_button, _give_button, _cancel_button, _upgrade_button]:
		if button != null and button.visible and button.focus_mode != FOCUS_NONE:
			buttons.append(button)

	if buttons.size() < 2:
		return

	for i in buttons.size():
		var button: Button = buttons[i]
		var above: Button = buttons[i - 1] if i > 0 else buttons[buttons.size() - 1]
		var below: Button = buttons[(i + 1) % buttons.size()]
		button.focus_neighbour_top = button.get_path_to(above)
		button.focus_neighbour_bottom = button.get_path_to(below)
		button.focus_neighbour_left = button.get_path_to(button)
		button.focus_neighbour_right = button.get_path_to(button)


func _update_give_font_color() -> void:
	if _give_text == null:
		return

	var color_name: = "font_color"
	if _give_button.disabled:
		color_name = "font_color_disabled"
	elif _give_button.pressed:
		color_name = "font_color_pressed"
	elif _give_button.has_focus():
		color_name = "font_color_focus"
	elif _give_button.is_hovered():
		color_name = "font_color_hover"

	var color: Color = _give_button.get_color(color_name)
	_give_text.add_color_override("font_color", color)
	_give_cost.add_color_override("font_color", color)


func _set_font_color(button: Button, color: Color) -> void:
	for color_name in ["font_color", "font_color_hover", "font_color_focus", "font_color_pressed"]:
		button.add_color_override(color_name, color)


func _clear_font_color(button: Button) -> void:
	for color_name in ["font_color", "font_color_hover", "font_color_focus", "font_color_pressed"]:
		button.remove_color_override(color_name)
