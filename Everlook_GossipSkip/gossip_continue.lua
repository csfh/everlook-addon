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

Everlook.gossip_continue = {}

-- What to choose from the facts alone, with a reason when the answer is nothing. `facts` holds whether Shift
-- holds automation back, whether the window offers quests, and the options the window lists.
function Everlook.gossip_continue.decide(facts)
	if facts.paused then return nil, "paused" end
	if facts.quests_present then return nil, "the window offers quests" end
	local options = facts.options
	if type(options) ~= "table" or #options ~= 1 then return nil, "not exactly one option" end
	local option = options[1]
	if blocked(option) then return nil, "a vendor, flight master, trainer or binder, or a type that cannot be classified" end
	if not facts.can_select or type(option.gossipOptionID) ~= "number" then return nil, "the option cannot be selected" end
	return option.gossipOptionID
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
	if module.paused() or not C_GossipInfo or type(C_GossipInfo.GetOptions) ~= "function" then
		return
	end
	local choice = Everlook.gossip_continue.decide({
		paused = false,
		quests_present = quests_present(),
		options = C_GossipInfo.GetOptions(),
		can_select = type(C_GossipInfo.SelectOption) == "function",
	})
	if choice then C_GossipInfo.SelectOption(choice) end
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
