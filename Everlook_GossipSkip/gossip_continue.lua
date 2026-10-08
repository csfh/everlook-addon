local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "gossip_continue"

local function blocked(option)
	if type(option) ~= "table" then
		return true
	end
	local kind = option.gossipOptionType or option.type
	if type(kind) == "string" then
		local name = kind:lower()
		return name == "vendor" or name == "taxi" or name == "trainer" or name == "binder"
	end
	local names = Enum and Enum.GossipOption
	if type(kind) ~= "number" or type(names) ~= "table" then
		return true
	end
	return kind == names.Vendor or kind == names.Taxi or kind == names.Trainer or kind == names.Binder
end

local function quests_present()
	if not C_GossipInfo then
		return false
	end
	local active = C_GossipInfo.GetActiveQuests and C_GossipInfo.GetActiveQuests() or {}
	local available = C_GossipInfo.GetAvailableQuests and C_GossipInfo.GetAvailableQuests() or {}
	return #active > 0 or #available > 0
end

local function continue_gossip()
	if module.paused() or quests_present() or not C_GossipInfo or type(C_GossipInfo.GetOptions) ~= "function" then
		return
	end
	local options = C_GossipInfo.GetOptions()
	if type(options) ~= "table" or #options ~= 1 or blocked(options[1]) then
		return
	end
	local option = options[1]
	if type(C_GossipInfo.SelectOption) ~= "function" or type(option.gossipOptionID) ~= "number" then
		return
	end
	C_GossipInfo.SelectOption(option.gossipOptionID)
end

module.register({
	addon = addon_name, page = "quests", order = 50,
	id = id,
	name = "Single gossip option",
	description = "Chooses the only gossip option when that window opens, unless it is a vendor, flight master, trainer, or binder. A quest on the window, more than one option, an option whose type cannot be classified, or Shift held leaves it alone, a window already open waits for the next one, nothing happens when the client cannot choose it, and turning this off leaves the next window.",
	events = { "GOSSIP_SHOW" },
	on_event = function()
		continue_gossip()
	end,
})
