extends Node

const MOD_ID: = "Hax-CoopItemsTrading"
const DEFAULT_PRICE: = 0.1
const LOCALES: = ["en", "fr", "zh", "ja", "ko", "zh_TW", "ru", "pl", "es", "pt", "de", "tr", "it"]


func _init() -> void:
	_load_translations()
	ModLoaderMod.install_script_extension("res://mods-unpacked/Hax-CoopItemsTrading/extensions/coop_item_popup.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/Hax-CoopItemsTrading/extensions/base_shop.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/Hax-CoopItemsTrading/extensions/item_description.gd")


func _ready() -> void:
	call_deferred("_register_mod_options")
	ModLoaderLog.info("Ready!", "Hax-CoopItemsTrading:Main")


func _disable() -> void:
	pass


func _load_translations() -> void:
	var translations_dir: = "res://mods-unpacked/Hax-CoopItemsTrading/translations"
	for locale in LOCALES:
		ModLoaderMod.add_translation(translations_dir.plus_file("coop_trade.%s.translation" % locale))


func _register_mod_options() -> void:
	var mod_options = get_node_or_null("/root/ModLoader/Oudstand-ModOptions/ModOptions")
	if mod_options == null:
		ModLoaderLog.info("Mod Options is not installed. Trade price stays at 10%.", MOD_ID)
		return

	if not get_tree().is_connected("node_added", self, "_on_node_added"):
		get_tree().connect("node_added", self, "_on_node_added")

	if not mod_options.call("get_registered_mods").has(MOD_ID):
		mod_options.call("register_mod_options", MOD_ID, {
			"tab_title": "COOP_TRADE_TAB",
			"options": [
				{
					"type": "slider",
					"id": "trade_price",
					"label": "COOP_TRADE_PRICE",
					"min": 0.0,
					"max": 2.0,
					"step": 0.01,
					"default": DEFAULT_PRICE
				}
			]
		})


func _on_node_added(node: Node) -> void:
	if not node is HBoxContainer or node.get_node_or_null("HSlider") == null:
		return

	var label: Label = node.get_node_or_null("Label")
	if label == null:
		return

	if label.text != tr("COOP_TRADE_PRICE") and label.text != "COOP_TRADE_PRICE":
		return

	call_deferred("_add_reset_button", node)


func _add_reset_button(slider: Node) -> void:
	if not is_instance_valid(slider):
		return

	var parent: Node = slider.get_parent()
	if parent == null or parent.get_node_or_null("CoopTradeResetButton") != null:
		return

	var button: = Button.new()
	button.name = "CoopTradeResetButton"
	button.text = "MENU_RESET_TO_DEFAULT"
	button.theme = slider.theme
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var label: Label = slider.get_node_or_null("Label")
	if label != null:
		button.add_font_override("font", label.get_font("font"))
	parent.add_child_below_node(slider, button)
	button.connect("pressed", self, "_on_reset_trade_price", [slider])


func _on_reset_trade_price(slider: Node) -> void:
	if not is_instance_valid(slider):
		return

	var hslider: HSlider = slider.get_node_or_null("HSlider")
	if hslider == null:
		return

	hslider.value = DEFAULT_PRICE
