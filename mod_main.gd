extends Node


func _init() -> void:
	ModLoaderMod.install_script_extension("res://mods-unpacked/Hax-CoopItemsTrading/extensions/coop_item_popup.gd")
	ModLoaderMod.install_script_extension("res://mods-unpacked/Hax-CoopItemsTrading/extensions/base_shop.gd")


func _ready() -> void:
	ModLoaderLog.info("Ready!", "Hax-CoopItemsTrading:Main")


func _disable() -> void:
	pass
