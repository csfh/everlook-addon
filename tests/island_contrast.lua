-- The island's text must stay readable on its most see-through setting over the brightest ground in the game.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local Everlook = { island_grid = { widths = { one = 1, two = 2 } } }
	local env = setmetatable({ Everlook = Everlook }, { __index = _G })
	env._G = env
	for _, file in ipairs({ "island_constants" }) do
		local chunk = assert(loadfile(source(file)))
		setfenv(chunk, env)
		chunk("Everlook_Island", Everlook)
	end
	local function linear(channel)
		return channel <= 0.03928 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4
	end
	local function luminance(r, g, b)
		return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
	end
	local function ratio(a, b)
		local high, low = math.max(a, b), math.min(a, b)
		return (high + 0.05) / (low + 0.05)
	end

	-- The option's lowest value, read from the declaration in smart_island.lua, which is too large to load on its own.
	local file = assert(io.open(source("smart_island"), "r"))
	local text = file:read("*a")
	file:close()
	local minimum = tonumber(text:match('opacity = { name = "Island opacity", default = %d+, min = (%d+)'))
	check("the lowest island opacity can be read", minimum ~= nil)

	local red, green, blue = 13 / 255, 15 / 255, 20 / 255
	local body_alpha = 1 - (1 - minimum / 100) * (1 - (minimum / 100) * 0.5)
	local ground = { 1, 1, 1 }
	local back = {}
	for index, channel in ipairs({ red, green, blue }) do back[index] = channel * body_alpha + ground[index] * (1 - body_alpha) end
	local background = luminance(back[1], back[2], back[3])
	local worst, worst_name = math.huge, nil
	for name, color in pairs(Everlook.island_const.COLORS) do
		local value = ratio(luminance(color[1], color[2], color[3]), background)
		if value < worst then worst, worst_name = value, name end
	end
	check("every island text colour reads at 4.5:1 on white ground at the lowest opacity (" .. tostring(worst_name) .. " " .. string.format("%.2f", worst) .. ")", worst >= 4.5)
end
