extends Reference

# Ids that cannot be given. A trailing * matches the start of the id.
# Items with can_be_looted turned off are blocked too: that is how character
# kits such as the Builder turrets, and spent items, are marked.
const EXCLUDED_ITEM_IDS: = [
	"item_builder_turret_*",
	"item_meca_evolved_leap",
	"item_mut_evolved_leap",
	"item_handcuffs",
	"item_knot",
	"item_shackles",
	"item_coupon",
]

# These stay tradable until that player has actually received the bonus.
const BONUS_ITEM_IDS: = [
	"item_snowball",
	"item_spyglass",
	"item_titanium_excess",
]

const NOTE_EXCLUDED: = "COOP_TRADE_EXCLUDED"
const NOTE_EXCLUDED_AFTER_BONUS: = "COOP_TRADE_EXCLUDED_AFTER_BONUS"

# 0–200. 10 is the default, 10% of the shop price. 0 makes the gift free.
const MOD_ID: = "Hax-CoopItemsTrading"
const MOD_OPTIONS_PATH: = "/root/ModLoader/Oudstand-ModOptions/ModOptions"
const DEFAULT_PRICE_PERCENT: = 10


# Read the slider each time. A cached copy stays at the default because Godot 3
# has no static variables, so moving the slider never reached the cost.
static func _percent() -> int:
	var percent: int = DEFAULT_PRICE_PERCENT
	var main_loop = Engine.get_main_loop()
	if not (main_loop is SceneTree):
		return percent

	var options = main_loop.root.get_node_or_null(MOD_OPTIONS_PATH)
	# Mod Options is optional. With it missing, the gift costs the default 10%.
	if options == null:
		return percent

	var value = options.call("get_value", MOD_ID, "trade_price")
	if value == null:
		return percent

	percent = int(round(float(value) * 100.0))
	if percent < 0:
		percent = 0
	elif percent > 200:
		percent = 200
	return percent


static func is_excluded(item: ItemParentData, player_index: int = -1) -> bool:
	if item == null or not item.can_be_looted:
		return true

	if _id_listed(item.my_id, EXCLUDED_ITEM_IDS):
		return true

	# The bonus counter belongs to the player who earned it, so only the giver is checked.
	if player_index >= 0 and _id_listed(item.my_id, BONUS_ITEM_IDS) and _bonus_gained(item, player_index):
		return true

	return false


static func trade_note(item: ItemParentData) -> String:
	if item == null or not RunData.is_coop_run:
		return ""

	var key: String = ""
	if _id_listed(item.my_id, EXCLUDED_ITEM_IDS) and not item.my_id.begins_with("item_builder_turret"):
		key = NOTE_EXCLUDED
	elif _id_listed(item.my_id, BONUS_ITEM_IDS):
		key = NOTE_EXCLUDED_AFTER_BONUS

	if key == "":
		return ""

	return "[color=#%s]%s[/color]" % [Utils.SECONDARY_FONT_COLOR.to_html(), TranslationServer.translate(key)]


static func can_hold_evolution(item: ItemParentData, player_index: int) -> bool:
	if item == null or (not item.is_meca and not item.is_mutant):
		return true

	var evolution: float = float(RunData.get_player_effect(Keys.stat_evolution_hash, player_index))
	var threshold: float = ItemService.EVOLUTION_CAMP_LOCK_THRESHOLD
	var dual: bool = RunData.is_dual_evolution(player_index)
	var meca_open: bool = evolution > threshold
	var mutant_open: bool = evolution < -threshold or (dual and evolution > threshold)

	if item.is_meca and not meca_open:
		return false

	if item.is_mutant and not mutant_open:
		return false

	return true


# True when this copy's one-shot "next wave" effect is still waiting, so the trade
# should take it along. A spent copy must not arm the effect again.
# Dig Site is not in this list: it stores [count, 3] and spawns when the wave
# number divides by 3, so moving it does not restart that schedule.
static func should_move_next_wave(item: ItemParentData, player_index: int) -> bool:
	if not _has_next_wave_effect(item):
		return true

	return _pending_copies(item, player_index) > 0


static func fix_next_wave_after_remove(item: ItemParentData, player_index: int, should_move: bool) -> void:
	if should_move or not _has_next_wave_effect(item):
		return

	# Lure's counter is a plain number, so unapply subtracts even after the wave
	# already cleared it. Put that subtraction back. The other next-wave effects
	# find nothing to remove once the wave has used them.
	for effect in item.effects:
		if effect.key == "extra_loot_aliens_next_wave":
			effect.apply(player_index)


static func fix_next_wave_after_add(item: ItemParentData, player_index: int, should_move: bool) -> void:
	if should_move or not _has_next_wave_effect(item):
		return

	var copies: int = 0
	for owned in RunData.get_player_items_ref(player_index):
		if owned == item:
			copies += 1

	for _i in copies:
		for effect in item.effects:
			if _is_next_wave_effect(effect):
				effect.unapply(player_index)


static func give_cost(item: ItemParentData, player_index: int) -> int:
	var percent: int = _percent()
	if percent <= 0:
		return 0

	var cost: int = ceil(float(shop_price(item, player_index)) * float(percent) / 100.0) as int
	return cost


static func shop_price(item: ItemParentData, player_index: int) -> int:
	var price: int = ItemService.get_value(RunData.current_wave, item.value, player_index, true, item is WeaponData, item.my_id_hash)

	if item is WeaponData and item.is_meca:
		var dlc_data = ItemService.get_dlc_data_by_id("primal_dread")
		if dlc_data != null:
			price += dlc_data.get_dismantle_price(RunData.current_wave, player_index)

	if RunData.get_player_effect_bool(Keys.hp_shop_hash, player_index):
		price = ceil(float(price) / 20.0) as int

	return 1 if price < 1 else price


static func other_players(player_index: int) -> Array:
	var others: Array = []
	for index in RunData.get_player_count():
		if index != player_index:
			others.append(index)
	return others


static func can_give(item: ItemParentData, player_index: int) -> bool:
	if not RunData.is_coop_run or item == null or item.is_locked or item is CharacterData or is_excluded(item, player_index):
		return false

	if item is WeaponData:
		return not RunData.get_player_effect_bool(Keys.lock_current_weapons_hash, player_index)

	return item is ItemData


static func can_receive(item: ItemParentData, player_index: int) -> bool:
	if item == null or item.is_locked or item is CharacterData or is_excluded(item):
		return false

	if not can_hold_evolution(item, player_index):
		return false

	if item is WeaponData:
		return can_receive_weapon(item, player_index)

	if item is ItemData:
		return RunData.get_remaining_max_nb_item(item, player_index) > 0

	return false


static func can_receive_weapon(weapon_data: WeaponData, player_index: int) -> bool:
	var min_weapon_tier = RunData.get_player_effect(Keys.min_weapon_tier_hash, player_index)
	var max_weapon_tier = RunData.get_player_effect(Keys.max_weapon_tier_hash, player_index)
	var no_melee_weapons = RunData.get_player_effect_bool(Keys.no_melee_weapons_hash, player_index)
	var no_ranged_weapons = RunData.get_player_effect_bool(Keys.no_ranged_weapons_hash, player_index)
	var no_duplicate_weapons = RunData.get_player_effect_bool(Keys.no_duplicate_weapons_hash, player_index)
	var lock_current_weapons = RunData.get_player_effect_bool(Keys.lock_current_weapons_hash, player_index)
	var weapon_slot_available: bool = RunData.has_weapon_slot_available(weapon_data, player_index)
	var player_has_weapon = RunData.get_combine_candidates(weapon_data, player_index).size() > 0
	var player_has_weapon_family = weapon_data.weapon_id in RunData.get_unique_weapon_ids(player_index)

	if weapon_data.tier > max_weapon_tier or weapon_data.tier < min_weapon_tier:
		return false

	if no_melee_weapons and weapon_data.type == WeaponType.MELEE:
		return false

	if no_ranged_weapons and weapon_data.type == WeaponType.RANGED:
		return false

	if lock_current_weapons and not weapon_slot_available:
		return false

	if player_has_weapon and not weapon_slot_available and weapon_data.upgrades_into != null and weapon_data.upgrades_into.tier <= max_weapon_tier:
		return true

	if no_duplicate_weapons and player_has_weapon_family:
		return false

	return weapon_slot_available


static func _id_listed(id: String, entries: Array) -> bool:
	for entry in entries:
		var pattern: String = entry
		if pattern.ends_with("*"):
			if id.begins_with(pattern.substr(0, pattern.length() - 1)):
				return true
		elif id == pattern:
			return true

	return false


static func _bonus_gained(item: ItemParentData, player_index: int) -> bool:
	if player_index < 0 or player_index >= RunData.tracked_item_effects.size():
		return false

	var tracked = RunData.tracked_item_effects[player_index]
	if not tracked.has(item.my_id_hash):
		return false

	return _tracked_total(tracked[item.my_id_hash]) > 0


static func _tracked_total(value) -> int:
	var total: int = 0
	if value is Array:
		for entry in value:
			total += int(entry)
		return total

	total = int(value)
	return total


static func _has_next_wave_effect(item: ItemParentData) -> bool:
	if item == null:
		return false

	for effect in item.effects:
		if _is_next_wave_effect(effect):
			return true

	return false


static func _is_next_wave_effect(effect) -> bool:
	if effect == null:
		return false

	if effect.key == "extra_enemies_next_wave" or effect.key == "extra_loot_aliens_next_wave":
		return true

	return effect.custom_key == "stats_next_wave"


static func _pending_copies(item: ItemParentData, player_index: int) -> int:
	var effects = RunData.get_player_effects(player_index)
	var found: bool = false
	var copies: int = 0

	for effect in item.effects:
		if not _is_next_wave_effect(effect):
			continue

		var effect_copies: int = _pending_copies_for_effect(effect, effects)
		if not found:
			found = true
			copies = effect_copies
		elif effect_copies < copies:
			copies = effect_copies

	return copies


static func _pending_copies_for_effect(effect, effects) -> int:
	var copies: int = 0
	var amount: int = int(effect.value)
	if amount < 0:
		amount = -amount
	if amount == 0:
		return 0

	if effect.key == "extra_enemies_next_wave":
		var group = effect.get("extra_group_data")
		if group == null or not effects.has(_effect_hash(effect, false)):
			return 0

		for entry in effects[_effect_hash(effect, false)]:
			if entry[0] == group.resource_path:
				copies = int(float(entry[1]) / float(amount))
				return copies

		return 0

	if effect.custom_key == "stats_next_wave":
		var custom_hash: int = _effect_hash(effect, true)
		if not effects.has(custom_hash):
			return 0

		for entry in effects[custom_hash]:
			if entry[0] == _effect_hash(effect, false):
				copies = int(abs(float(entry[1])) / float(amount))
				return copies

		return 0

	var key_hash: int = _effect_hash(effect, false)
	if not effects.has(key_hash):
		return 0

	copies = int(float(effects[key_hash]) / float(amount))
	return copies


static func _effect_hash(effect, custom: bool) -> int:
	if custom:
		if effect.custom_key_hash != Keys.empty_hash:
			return effect.custom_key_hash
		return Keys.generate_hash(effect.custom_key)

	if effect.key_hash != Keys.empty_hash:
		return effect.key_hash

	return Keys.generate_hash(effect.key)
