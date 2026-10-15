-- The core tooltip service: one post-call per kind, isolation between owners, and lines added once.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load(extra)
		local Everlook = {}
		local env = setmetatable({}, { __index = _G })
		env._G = env
		env.Enum = { TooltipDataType = { Item = 0, Spell = 1, Unit = 2 } }
		for key, value in pairs(extra or {}) do env[key] = value end
		local chunk = assert(loadfile(source("tooltips")))
		setfenv(chunk, env)
		chunk("Everlook", Everlook)
		return Everlook.tooltips, env
	end
	local function tooltip()
		local shown = { lines = 0 }
		function shown:HasScript() return true end
		function shown:HookScript(_, callback) self.cleared = callback end
		function shown:NumLines() return self.lines end
		function shown:AddLine() self.lines = self.lines + 1 end
		return shown
	end

	do
		local posts = {}
		local service = load({ TooltipDataProcessor = { AddTooltipPostCall = function(kind, callback) posts[#posts + 1] = { kind = kind, callback = callback } end } })
		local order = {}
		service.add("first", "item", function() order[#order + 1] = "first" end)
		service.add("second", "item", function() order[#order + 1] = "second" end)
		service.add("second", "unit", function() order[#order + 1] = "unit" end)
		check("two owners of one kind share a single post-call", #posts == 2 and posts[1].kind == 0 and posts[2].kind == 2)
		posts[1].callback(tooltip(), { id = 1 })
		check("every owner is called, in the order they were added", table.concat(order, ",") == "first,second")
		service.add("second", "unit", service.add)
		check("an owner that adds a different callback for a kind is called for both", #posts == 2)
	end

	do
		local posts, handled = {}, {}
		local service = load({
			TooltipDataProcessor = { AddTooltipPostCall = function(kind, callback) posts[kind] = callback end },
			geterrorhandler = function() return function(message) handled[#handled + 1] = message end end,
		})
		local ran = false
		service.add("breaks", "item", function() error("boom") end)
		service.add("steady", "item", function() ran = true end)
		posts[0](tooltip(), {})
		check("an owner's error does not stop the next owner", ran == true)
		check("the error is shown by the game's handler and counted for its owner", #handled == 1 and tostring(handled[1]):find("boom", 1, true) and service.failures.breaks == 1 and service.failures.steady == nil)
	end

	do
		local service = load()
		local tip = tooltip()
		check("lines are added the first time for a key", service.once("owner", tip, "item:1") == true)
		tip:AddLine()
		check("the same key again adds nothing", service.once("owner", tip, "item:1") == false and service.done("owner", tip, "item:1") == true)
		check("another owner has its own turn", service.once("other", tip, "item:1") == true)
		check("another key is a new tooltip", service.once("owner", tip, "item:2") == true)
		tip:AddLine()
		tip.cleared(tip)
		check("a cleared tooltip takes lines again", service.once("owner", tip, "item:2") == true)
		tip:AddLine()
		tip.lines = 0
		check("a tooltip rebuilt without being cleared takes lines again", service.once("owner", tip, "item:2") == true)
	end

	do
		local hooked = {}
		local GameTooltip = { HasScript = function(_, script) return script == "OnTooltipSetItem" or script == "OnTooltipSetUnit" end,
			HookScript = function(_, script, callback) hooked[script] = callback end }
		local service = load({ Enum = false, GameTooltip = GameTooltip })
		local called
		service.add("old", "item", function() called = true end)
		check("a client without post-calls falls back to the item script", hooked.OnTooltipSetItem ~= nil)
		hooked.OnTooltipSetItem(tooltip())
		check("the fallback calls the owner", called == true)
		local none = load({ Enum = false })
		check("a client with no way to add lines is left alone", pcall(none.add, "owner", "spell", function() end))
	end
end
