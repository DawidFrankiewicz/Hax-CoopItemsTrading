extends Reference

# Ids that cannot be given. A trailing * matches the start of the id.
# Items with can_be_looted turned off are blocked too: that is how character
# kits such as the Builder turrets, and spent items, are marked.
const EXCLUDED_ITEM_IDS: = [
	"item_builder_turret_*",
]


static func is_excluded(item: ItemParentData) -> bool:
	if item == null or not item.can_be_looted:
		return true

	var id: String = item.my_id
	for entry in EXCLUDED_ITEM_IDS:
		var pattern: String = entry
		if pattern.ends_with("*"):
			if id.begins_with(pattern.substr(0, pattern.length() - 1)):
				return true
		elif id == pattern:
			return true

	return false


static func give_cost(item: ItemParentData, player_index: int) -> int:
	var cost: int = ceil(float(shop_price(item, player_index)) * 0.1) as int
	return 1 if cost < 1 else cost


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
	if not RunData.is_coop_run or item == null or item.is_locked or item is CharacterData or is_excluded(item):
		return false

	if item is WeaponData:
		return not RunData.get_player_effect_bool(Keys.lock_current_weapons_hash, player_index)

	return item is ItemData


static func can_receive(item: ItemParentData, player_index: int) -> bool:
	if item == null or item.is_locked or item is CharacterData or is_excluded(item):
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
