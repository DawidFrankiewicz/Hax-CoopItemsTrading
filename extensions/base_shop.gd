extends "res://ui/menus/shop/base_shop.gd"

const TRADE_PATH: = "res://mods-unpacked/Hax-CoopItemsTrading/extensions/trade.gd"


func _trade():
	return load(TRADE_PATH)


func shake_player_currency(player_index: int) -> void:
	var gold_label = _get_gold_label(player_index)
	if gold_label != null:
		UIService._reached_max_shake(gold_label.get_parent())


func give_item_to_player(item_data: ItemParentData, giver_index: int, receiver_index: int) -> void:
	if not RunData.is_coop_run or item_data == null or giver_index == receiver_index:
		return

	if receiver_index < 0 or receiver_index >= RunData.get_player_count():
		return

	item_data = _owned_instance(item_data, giver_index)
	if item_data == null:
		return

	if not _trade().can_give(item_data, giver_index) or not _trade().can_receive(item_data, receiver_index):
		return

	var cost: int = _trade().give_cost(item_data, giver_index)
	if cost > 0 and RunData.get_player_currency(giver_index) < cost:
		shake_player_currency(giver_index)
		return

	var giver_reroll_before: int = RunData.get_player_effect(Keys.reroll_price_hash, giver_index)
	var receiver_reroll_before: int = RunData.get_player_effect(Keys.reroll_price_hash, receiver_index)
	var is_weapon: bool = item_data is WeaponData
	var is_hourglass: bool = item_data.my_id_hash == Keys.item_hourglass_hash
	var tracked_value: = 0
	var damage_dealt: = 0
	var move_next_wave: bool = _trade().should_move_next_wave(item_data, giver_index)

	# Move focus before any icon is freed. Rebuilding the whole gear left the focus
	# emulator pointing at a queue_freed inventory icon, and its outline then called
	# get_meta on that freed control.
	_close_giver_popup(giver_index)
	_focus_shop_button_now(giver_index)

	if is_weapon:
		tracked_value = item_data.tracked_value
		damage_dealt = item_data.dmg_dealt_last_wave
		var weapons: Array = RunData.get_player_weapons_ref(giver_index)
		var weapon_index: int = weapons.find(item_data)
		if weapon_index == -1:
			return
		RunData.remove_weapon_by_index(weapon_index, giver_index)
	else:
		RunData.remove_item(item_data, giver_index, false, false)
		_trade().fix_next_wave_after_remove(item_data, giver_index, move_next_wave)

	_remove_gear_element(giver_index, item_data)
	_sync_stack_icon(giver_index, item_data)

	var result: int = _give_to_receiver(item_data, receiver_index, move_next_wave)
	if result < 0:
		_restore_to_giver(item_data, giver_index, tracked_value, damage_dealt)
		return

	if cost > 0:
		RunData.remove_currency(cost, giver_index)
	_update_stats(giver_index)
	_update_stats(receiver_index)
	_get_shop_items_container(giver_index).reload_shop_items()
	_get_shop_items_container(receiver_index).reload_shop_items()
	_sync_rerolls_after_trade(giver_index, giver_reroll_before)
	_sync_rerolls_after_trade(receiver_index, receiver_reroll_before)

	if is_hourglass:
		update_next_wave_ui()

	_on_player_focus_lost(giver_index)


# A stacked icon keeps the first copy. After that copy is given away the icon still
# points at it, so later gives and give-backs have to use a copy this player still holds.
func _owned_instance(item_data: ItemParentData, player_index: int):
	if item_data == null:
		return null

	if item_data is WeaponData:
		if RunData.get_player_weapons_ref(player_index).find(item_data) != -1:
			return item_data
		return null

	var items: Array = RunData.get_player_items_ref(player_index)
	if items.find(item_data) != -1:
		return item_data

	var flavor: int = ItemService.get_flavor(item_data)
	for owned in items:
		if owned.my_id == item_data.my_id and ItemService.get_flavor(owned) == flavor:
			return owned

	return null


# 1 when the weapon merged, 0 when it was added, -1 when it could not be given.
func _give_to_receiver(item_data: ItemParentData, receiver_index: int, move_next_wave: bool) -> int:
	if item_data is WeaponData:
		return _give_weapon_to_receiver(item_data, receiver_index)

	var duplicates = RunData.get_player_effect(Keys.duplicate_item_hash, receiver_index)
	if typeof(duplicates) == TYPE_ARRAY and not duplicates.empty():
		_release_gear_focus(receiver_index)

	buy_item(item_data, receiver_index)
	_trade().fix_next_wave_after_add(item_data, receiver_index, move_next_wave)
	_sync_stack_icon(receiver_index, item_data)
	return 0


func _give_weapon_to_receiver(weapon: WeaponData, receiver_index: int) -> int:
	var tracked_value: int = weapon.tracked_value
	var damage_dealt: int = weapon.dmg_dealt_last_wave
	var elements = _gear_elements(receiver_index, weapon)
	var merge: bool = not RunData.has_weapon_slot_available(weapon, receiver_index)

	if not merge:
		var added: WeaponData = RunData.add_weapon(weapon, receiver_index)
		added.tracked_value = tracked_value
		added.dmg_dealt_last_wave = damage_dealt
		elements.add_element(added)
		return 0

	var partner = _get_combine_partner(weapon, receiver_index)
	if partner == null:
		return -1

	_focus_away_from_item(receiver_index, partner)
	var added: WeaponData = RunData.add_weapon(weapon, receiver_index)
	added.tracked_value = tracked_value
	added.dmg_dealt_last_wave = damage_dealt
	elements.add_element(added)
	_combine_weapon(added, receiver_index, false)
	return 1


func _restore_to_giver(item_data: ItemParentData, giver_index: int, tracked_value: int, damage_dealt: int) -> void:
	if item_data is WeaponData:
		var restored: WeaponData = RunData.add_weapon(item_data, giver_index)
		restored.tracked_value = tracked_value
		restored.dmg_dealt_last_wave = damage_dealt
		_gear_elements(giver_index, restored).add_element(restored)
		return

	RunData.add_item(item_data, giver_index)
	_gear_elements(giver_index, item_data).add_element(item_data, true)


func _refresh_items_if_bought_item_was_consumed(player_index: int, bought_item: ItemData) -> void:
	if RunData.get_player_items(player_index).has(bought_item):
		return

	_release_gear_focus(player_index)
	._refresh_items_if_bought_item_was_consumed(player_index, bought_item)


func _close_giver_popup(giver_index: int) -> void:
	_popup_manager.reset_focus(giver_index)
	if has_method("_get_coop_player_container"):
		call("_get_coop_player_container", giver_index).on_hide_focused_inventory_popup()


func _gear_elements(player_index: int, item_data: ItemParentData):
	var gear = _get_gear_container(player_index)
	if item_data is WeaponData:
		return gear.weapons_container._elements
	return gear.items_container._elements


func _sync_stack_icon(player_index: int, item_data: ItemParentData) -> void:
	if item_data is WeaponData:
		return

	var flavor: int = ItemService.get_flavor(item_data)
	var owned_copies: Array = []
	for owned in RunData.get_player_items_ref(player_index):
		if owned.my_id == item_data.my_id and ItemService.get_flavor(owned) == flavor:
			owned_copies.append(owned)

	var icon = null
	for child in _gear_elements(player_index, item_data).get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion() or child.item == null:
			continue
		if child.item.my_id != item_data.my_id or ItemService.get_flavor(child.item) != flavor:
			continue
		icon = child
		break

	if icon == null:
		return

	if owned_copies.empty():
		_focus_away_from_item(player_index, item_data)
		icon.queue_free()
		return

	icon.item = owned_copies[0]
	while icon.current_number > owned_copies.size():
		icon.remove_from_number()
	while icon.current_number < owned_copies.size():
		icon.add_to_number()


func _remove_gear_element(player_index: int, item_data: ItemParentData) -> void:
	var elements = _gear_elements(player_index, item_data)
	if _icon_will_be_freed(elements, item_data):
		_focus_away_from_item(player_index, item_data)

	if item_data is WeaponData:
		elements.remove_element(item_data, 1, true)
	else:
		elements.remove_element(item_data, 1, false)


func _icon_will_be_freed(elements, item_data: ItemParentData) -> bool:
	for child in elements.get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion() or child.item == null:
			continue
		var same: bool = child.item == item_data if item_data is WeaponData else child.item.my_id == item_data.my_id
		if same:
			return child.current_number <= 1
	return false


func _focus_away_from_item(player_index: int, item_data: ItemParentData) -> void:
	var emulator = Utils.get_focus_emulator(player_index)
	if emulator == null or not is_instance_valid(emulator.focused_control):
		return

	var focused: Control = emulator.focused_control
	for child in _gear_elements(player_index, item_data).get_children():
		if not is_instance_valid(child) or child.is_queued_for_deletion() or child.item == null:
			continue
		var same: bool = child.item == item_data if item_data is WeaponData else child.item.my_id == item_data.my_id
		if same and (focused == child or child.is_a_parent_of(focused)):
			_focus_shop_button_now(player_index)
			return


func _release_gear_focus(player_index: int) -> void:
	var emulator = Utils.get_focus_emulator(player_index)
	if emulator == null or not is_instance_valid(emulator.focused_control):
		return

	if _get_gear_container(player_index).is_a_parent_of(emulator.focused_control):
		_focus_shop_button_now(player_index)


func _focus_shop_button_now(player_index: int) -> void:
	var button = _get_reroll_button(player_index) if _reroll_price[player_index] == 0 else _get_go_button(player_index)
	if not is_instance_valid(button):
		return

	var emulator = Utils.get_focus_emulator(player_index)
	if emulator != null:
		emulator.focused_control = button
	else:
		button.grab_focus()


func _sync_rerolls_after_trade(player_index: int, reroll_price_before: int) -> void:
	var total_free_rerolls: int = RunData.get_player_effect(Keys.free_rerolls_hash, player_index)
	if total_free_rerolls > _initial_free_rerolls[player_index]:
		var new_rerolls: int = total_free_rerolls - _initial_free_rerolls[player_index]
		_initial_free_rerolls[player_index] = total_free_rerolls
		_free_rerolls[player_index] += new_rerolls

	var reroll_price_after: int = RunData.get_player_effect(Keys.reroll_price_hash, player_index)
	if reroll_price_after != reroll_price_before and _free_rerolls[player_index] <= 0 and not _has_bonus_free_reroll[player_index]:
		var result: Array = ItemService.get_reroll_price(RunData.current_wave, _paid_reroll_count[player_index], player_index)
		_reroll_price[player_index] = result[0]
		_reroll_discount[player_index] = result[1]

	set_reroll_button_price(player_index)
