local addon_name = ...
local Everlook = Everlook
local kit = Everlook.island_feed_kit
local plain_number, now, option, notify = kit.plain_number, kit.now, kit.option, kit.notify
local dismiss_map, map_pending, inspect_item = kit.dismiss_map, kit.map_pending, kit.inspect_item
local state = {}

-- Rare loot, including items that go straight to the bags and bonus rolls.
local function rare_quality()
	local enum = Enum and Enum.ItemQuality and Enum.ItemQuality.Rare
	local value = plain_number(enum)
	return value or 3
end

-- %s, %d, %%, and positional %1$s / %2$d. One item capture, and at most one count.
-- Anything else fails closed so a locale cannot announce the wrong text.
local function pattern_from(format_text)
	if type(format_text) ~= "string" or format_text == "" or (issecretvalue and issecretvalue(format_text)) then return nil end
	local parts = {}
	local captures, link_at, count_at = 0, nil, nil
	local index = 1
	while index <= #format_text do
		local percent = format_text:find("%", index, true)
		if not percent then
			parts[#parts + 1] = format_text:sub(index):gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
			break
		end
		if percent > index then
			parts[#parts + 1] = format_text:sub(index, percent - 1):gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
		end
		local cursor = percent + 1
		if format_text:sub(cursor, cursor):find("%d") then
			while format_text:sub(cursor, cursor):find("%d") do cursor = cursor + 1 end
			if format_text:sub(cursor, cursor) ~= "$" then return nil end
			cursor = cursor + 1
		end
		local spec = format_text:sub(cursor, cursor)
		if spec == "s" then
			if link_at then return nil end
			captures = captures + 1
			link_at = captures
			parts[#parts + 1] = "(.+)"
		elseif spec == "d" then
			if count_at then return nil end
			captures = captures + 1
			count_at = captures
			parts[#parts + 1] = "(%d+)"
		elseif spec == "%" then
			parts[#parts + 1] = "%%"
		else
			return nil
		end
		index = cursor + 1
	end
	if not link_at or (count_at and captures ~= 2) or (not count_at and captures ~= 1) then return nil end
	return { pattern = "^" .. table.concat(parts) .. "$", link = link_at, count = count_at }
end

local function item_id_from(link)
	if type(link) ~= "string" then return nil end
	local id = link:match("item:(%d+)")
	return id and tonumber(id) or nil
end

local function item_name(link, item_id)
	local name = type(link) == "string" and link:match("%[(.-)%]") or nil
	if type(name) == "string" and name:find("%S") then return name end
	return "Item " .. item_id
end

local function add_loot_pattern(format_text, counted, multiples, singles)
	local pattern = pattern_from(format_text)
	if not pattern then return end
	if counted and pattern.count then multiples[#multiples + 1] = pattern
	elseif not counted and not pattern.count then singles[#singles + 1] = pattern end
end

local function matched_loot(message, pattern)
	local first, second = message:match(pattern.pattern)
	local values = { first, second }
	local link = values[pattern.link]
	if type(link) ~= "string" or not link:find("%S") then return nil end
	if not pattern.count then return link, 1 end
	local count = plain_number(tonumber(values[pattern.count]))
	if not count or count < 1 or count % 1 ~= 0 then return nil end
	return link, count
end

-- Loot-window, straight-to-bag, and bonus-roll lines. Crafted items use another global.
local function loot_link(message)
	local multiples, singles = {}, {}
	add_loot_pattern(LOOT_ITEM_SELF_MULTIPLE, true, multiples, singles)
	add_loot_pattern(LOOT_ITEM_SELF, false, multiples, singles)
	add_loot_pattern(LOOT_ITEM_PUSHED_SELF_MULTIPLE, true, multiples, singles)
	add_loot_pattern(LOOT_ITEM_PUSHED_SELF, false, multiples, singles)
	add_loot_pattern(LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE, true, multiples, singles)
	add_loot_pattern(LOOT_ITEM_BONUS_ROLL_SELF, false, multiples, singles)
	for index = 1, #multiples do
		local link, count = matched_loot(message, multiples[index])
		if link then return link, count end
	end
	for index = 1, #singles do
		local link, count = matched_loot(message, singles[index])
		if link then return link, count end
	end
end

local function loot(message)
	if not option("feed_loot") then
		dismiss_map(state.loot_handles)
		if not map_pending(state.loot_handles) then state.loot, state.loot_handles = nil, nil end
		return
	end
	if type(message) ~= "string" or (issecretvalue and issecretvalue(message)) then return end
	local link, count = loot_link(message)
	local item_id = item_id_from(link)
	count = plain_number(count)
	if not item_id or not count or count < 1 then return end
	if not C_Item or not C_Item.GetItemQualityByID then return end
	local quality = C_Item.GetItemQualityByID(item_id)
	quality = plain_number(quality)
	if not quality or quality < rare_quality() then return end
	state.loot = state.loot or {}
	state.loot_handles = state.loot_handles or {}
	local time = now()
	local row = state.loot[item_id]
	if not row or time - row.at > 2 then
		row = { count = 0, at = time, seq = row and row.seq + 1 or 1 }
		state.loot[item_id] = row
	end
	row.count = row.count + count
	row.at = time
	local name = item_name(link, item_id)
	local handle_key = item_id .. ":" .. row.seq
	state.loot_handles[handle_key] = notify({
		source = "everlook.loot", key = "loot:" .. handle_key, kind = "loot", stack = "loot",
		text = row.count > 1 and (name .. " x" .. row.count) or name,
		detail = "Rare loot", item_id = item_id,
		actions = { { id = "inspect", label = "Inspect", type = "callback", on_click = inspect_item(item_id) } },
	})
end

local function settle()
	if option("feed_loot") then return end
	dismiss_map(state.loot_handles)
	if not map_pending(state.loot_handles) then state.loot, state.loot_handles = nil, nil end
end

Everlook.module.extend("smart_island", {
	id = "loot", addon = addon_name, order = 20,
	options = {
		feed_loot = { name = "Rare loot", default = false, description = "Tells you when you loot a rare item or better, including one that goes straight to your bags or comes from a bonus roll. The same item within two seconds adds to its count, later rare loot joins that notice while it is still up, an item below rare, someone else's loot, a crafted item, or text or a quality the client hides stays quiet, and turning this off clears the notice.", presets = { Quiet = false, Standard = true, Informative = true } },
	},
	sections = { { name = "Notices", keys = { "feed_loot" } } },
	events = { "CHAT_MSG_LOOT", "PLAYER_ENTERING_WORLD" },
	on_event = function(event, message)
		if event == "CHAT_MSG_LOOT" then loot(message) else settle() end
	end,
	apply = function(enabled)
		if enabled then settle() else state = {} end
	end,
	refresh = function(force)
		if not force then settle() end
	end,
})
