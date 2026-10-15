-- The coin mark on the reward choice that sells for the most.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)

	local function setup(options)
		options = options or {}
		local Everlook, registered
		Everlook = { module = { enabled = function() return options.enabled ~= false end, get = function() return false end,
			register = function(spec) registered = spec end } }
		local env = setmetatable({ Everlook = Everlook }, { __index = _G })
		env._G = env
		local after = {}
		env.C_Timer = { After = function(_, callback) after[#after + 1] = callback end }
		env.hooksecurefunc = function(name, callback) env.hooked = { name = name, callback = callback } end
		-- Two choices and a plain reward button: the mark goes on a choice only.
		local function button(kind, id)
			local item = { type = kind, objectType = "item", id = id, shown = true, textures = {} }
			function item:GetID() return self.id end
			function item:IsShown() return self.shown end
			function item:CreateTexture()
				local texture = { shown = false }
				function texture:SetTexture(path) self.path = path end
				function texture:SetSize() end
				function texture:SetPoint() end
				function texture:SetShown(value) self.shown = value end
				function texture:Hide() self.shown = false end
				function texture:Show() self.shown = true end
				self.textures[#self.textures + 1] = texture
				return texture
			end
			return item
		end
		local buttons = { button("choice", 1), button("choice", 2), button("choice", 3), button("reward", 1) }
		env.QuestInfoFrame = { questLog = false, rewardsFrame = { RewardButtons = buttons } }
		local items = options.items or { [1] = { count = 1, price = 100 }, [2] = { count = 5, price = 40 }, [3] = { count = 1, price = 150 } }
		env.GetQuestItemInfo = function(kind, index)
			local item = kind == "choice" and items[index]
			if not item then return end
			return "Item " .. index, 1, item.count, 1, true, 1000 + index
		end
		env.GetQuestItemLink = function(kind, index) return kind == "choice" and items[index] and ("item:" .. (1000 + index)) or nil end
		env.C_Item = { GetItemInfo = function(link)
			local index = tonumber(tostring(link):match("(%d+)$")) - 1000
			local item = items[index]
			if item and item.price ~= nil then return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, item.price end
		end }
		env.GetNumQuestChoices = function() return 3 end
		env.QuestInfo_ShowRewards = function() end
		local chunk = assert(loadfile(source("reward_marks")))
		setfenv(chunk, env)
		chunk("Everlook_RewardMarks", Everlook)
		local function run_pending()
			local queued = after
			after = {}
			for _, callback in ipairs(queued) do callback() end
		end
		return env, buttons, registered, run_pending, items, function() return #after end
	end
	local function marked(buttons)
		local list = {}
		for index, item in ipairs(buttons) do
			for _, texture in ipairs(item.textures) do
				if texture.shown then list[#list + 1] = index end
			end
		end
		return table.concat(list, ",")
	end

	local env, buttons, spec, run = setup()
	check("the module registers on the quests page and starts off", spec and spec.page == "quests" and spec.id == "reward_marks")
	spec.apply(true)
	check("it follows the game's own reward display", env.hooked and env.hooked.name == "QuestInfo_ShowRewards")
	env.hooked.callback()
	check("nothing is drawn before the next frame", marked(buttons) == "")
	run()
	check("the choice that sells for the most (a stack counts) carries the mark", marked(buttons) == "2")
	env.hooked.callback()
	run()
	check("showing the rewards again does not stack marks", marked(buttons) == "2")

	local env2, buttons2, spec2, run2, items2, pending2 = setup({ items = { [1] = { count = 1, price = 100 }, [2] = { count = 1, price = nil }, [3] = { count = 1, price = 50 } } })
	spec2.apply(true)
	env2.hooked.callback()
	run2()
	check("while a price is not cached nothing is marked, and a retry is waiting", marked(buttons2) == "" and pending2() >= 1)
	items2[2].price = 400
	run2()
	check("when the price arrives the best choice is marked", marked(buttons2) == "2")

	local env3, buttons3, spec3, run3, _, pending3 = setup({ items = { [1] = { count = 1, price = nil }, [2] = { count = 1, price = nil }, [3] = { count = 1, price = nil } } })
	spec3.apply(true)
	env3.hooked.callback()
	for _ = 1, 12 do run3() end
	check("retries are bounded", pending3() == 0 and marked(buttons3) == "")

	local env4, buttons4, spec4, run4 = setup({ items = { [1] = { count = 1, price = 0 }, [2] = { count = 1, price = 0 }, [3] = { count = 1, price = 0 } } })
	spec4.apply(true)
	env4.hooked.callback()
	run4()
	check("rewards that sell for nothing are not marked", marked(buttons4) == "")

	local env5, buttons5, spec5, run5 = setup({ items = { [1] = { count = 1, price = 70 }, [2] = { count = 1, price = 70 }, [3] = { count = 1, price = 10 } } })
	spec5.apply(true)
	env5.hooked.callback()
	run5()
	check("a tie for the best price marks neither", marked(buttons5) == "")

	local env6, buttons6, spec6, run6 = setup()
	spec6.apply(true)
	env6.hooked.callback()
	run6()
	spec6.apply(false)
	check("turning the module off takes the mark away", marked(buttons6) == "")

	local env7, buttons7, spec7, run7 = setup({ enabled = false })
	spec7.apply(true)
	env7.hooked.callback()
	run7()
	check("a disabled module draws nothing", marked(buttons7) == "")

	local env8, buttons8, spec8, run8 = setup()
	for index = 2, 3 do buttons8[index].shown = false end
	spec8.apply(true)
	env8.hooked.callback()
	run8()
	check("a single choice needs no mark", marked(buttons8) == "")
end
