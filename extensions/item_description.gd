extends "res://ui/menus/shop/item_description.gd"

const TRADE_PATH: = "res://mods-unpacked/Hax-CoopItemsTrading/extensions/trade.gd"


func _generate_description_effects(player_index, effects: Array, colored: bool = true, activate_tab: bool = true, removed_effects: Array = []):
	._generate_description_effects(player_index, effects, colored, activate_tab, removed_effects)

	var note: String = load(TRADE_PATH).trade_note(item)
	if note == "":
		return

	var line: EffectLine = effect_line.instance()
	get_effects().add_child(line)
	line._display_special_text(note, null)
