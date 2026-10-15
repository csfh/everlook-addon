-- The data addon's reader, and the tooltip line that uses it.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load_data()
		local env = setmetatable({}, { __index = _G })
		env._G = env
		local chunk = assert(loadfile(root .. "/Everlook_Data/data.lua"))
		setfenv(chunk, env)
		chunk("Everlook_Data", {})
		return env.Everlook_Data
	end

	local data = load_data()
	data.chunk("drops", 10, "\n10|448:12:Hogger;449:3:Fang\n11|7:1:Rat\n")
	data.chunk("drops", 500, "\n500|9:4:Boar\n")
	check("a record is found by its id in the chunk that starts at or before it", data.find("drops", 11) == "7:1:Rat" and data.find("drops", 500) == "9:4:Boar")
	check("an id that is not in the pack, or before the first chunk, is nil", data.find("drops", 12) == nil and data.find("drops", 5) == nil and data.find("nothing", 11) == nil and data.find("drops", "x") == nil)
	check("a prefix of an id is not the id", data.find("drops", 1) == nil)
	local list = data.drops(10)
	check("drops lists the creatures in the order the pack has them", #list == 2 and list[1].npc == 448 and list[1].drops == 12 and list[1].name == "Hogger" and list[2].name == "Fang")
	check("a name may hold a colon", (function() data.chunk("drops", 600, "\n600|1:1:Lord: of Rats\n"); return data.drops(600)[1].name == "Lord: of Rats" end)())

	-- The real pack that ships: every chunk the meta names is there and an item in it resolves.
	local real = load_data()
	for _, name in ipairs({ "meta", "drops_1" }) do
		local chunk = assert(loadfile(root .. "/Everlook_Data/" .. name .. ".lua"))
		setfenv(chunk, setmetatable({ Everlook_Data = real }, { __index = _G }))
		chunk()
	end
	check("the shipped pack states its version and finds a record for the first id of each chunk", type(real.version()) == "string" and #real.version() == 12
		and real.drops(real.meta.kinds.drops[1]) ~= nil)

	-- The tooltip line.
	local function tooltip_module(extra, state)
		local Everlook
		local handlers = {}
		Everlook = {
			module = { get = function() return true end, enabled = function() return true end, register = function(def) Everlook.def = def end },
			data_addons = state or {},
			tooltips = { add = function(_, kind, fn) handlers[kind] = fn end, once = function() return true end },
			items = { id_from_link = function() end },
		}
		local env = setmetatable({ Everlook = Everlook }, { __index = _G })
		env._G = env
		for key, value in pairs(extra) do env[key] = value end
		local chunk = assert(loadfile(root .. "/Everlook_UsefulTooltips/useful_tooltips.lua"))
		setfenv(chunk, env)
		chunk("Everlook_UsefulTooltips")
		Everlook.def.apply(true)
		return Everlook, handlers.item
	end
	local function dropped(lines)
		for _, text in ipairs(lines) do
			if text:find("^Dropped by") then return true end
		end
		return false
	end
	local function lines_for(handler, item_id)
		local lines = {}
		handler({ AddLine = function(_, text) lines[#lines + 1] = text end }, { id = item_id })
		return lines
	end

	local Everlook, item = tooltip_module({ Everlook_Data = data })
	check("the module registers a pack option that is on by default", Everlook.def.options.pack and Everlook.def.options.pack.default == true)
	local lines = lines_for(item, 10)
	check("a loaded pack adds who drops the item", lines[#lines] == "Dropped by Hogger, Fang")
	data.chunk("drops", 700, "\n700|1:5:A;2:4:B;3:3:C;4:2:D;5:1:E\n")
	lines = lines_for(item, 700)
	check("more than three droppers say how many more", lines[#lines] == "Dropped by A, B, C and 2 more")
	check("an item nobody has seen drop gets no line", not dropped(lines_for(item, 12)))

	local loads = 0
	local Missing, missing_item = tooltip_module({}, {})
	Missing.load_data_addon = function(name)
		loads = loads + 1
		Missing.data_addons[name] = { state = "failed" }
		return false
	end
	lines_for(missing_item, 10)
	lines_for(missing_item, 10)
	check("a pack that cannot load is asked for once, and the tooltip stays as it was", loads == 1 and not dropped(lines_for(missing_item, 10)))

	local Waiting, waiting_item = tooltip_module({}, {})
	local waiting_loads = 0
	Waiting.load_data_addon = function() waiting_loads = waiting_loads + 1; return false end
	lines_for(waiting_item, 10)
	check("a pack that waits for combat to end is asked again at the next tooltip", waiting_loads == 1 and not dropped(lines_for(waiting_item, 10)) and waiting_loads == 2)
end
