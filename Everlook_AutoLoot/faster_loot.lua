local addon_name = ...
local Everlook = Everlook
local module = Everlook.module

module.register({
	addon = addon_name, page = "loot", order = 10,
	id = "faster_loot", name = "Faster looting",
	description = "Loots each unlocked slot right away when the loot window opens with auto loot. A locked slot stays put, a window without auto loot stays for you to loot by hand, loot confirmations still wait for you, holding Shift skips that window, turning this off leaves looting to the game, and nothing happens when the client cannot loot a slot.",
	events = { "LOOT_OPENED" },
	on_event = function(_, auto_loot)
		if not auto_loot or module.paused() or not GetNumLootItems or not LootSlot then return end
		for slot = GetNumLootItems(), 1, -1 do
			local _, _, _, _, _, locked = GetLootSlotInfo(slot)
			if not locked then LootSlot(slot) end
		end
	end,
})
