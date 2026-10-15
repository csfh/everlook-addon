-- A title that does not fit: the longest wording that does, then a cut at a word, never inside one.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local Everlook = {}
	local env = setmetatable({ Everlook = Everlook }, { __index = _G })
	env._G = env
	local chunk = assert(loadfile(source("island_row")))
	setfenv(chunk, env)
	chunk("Everlook", Everlook)
	local fit = Everlook.island_row.fit
	local function width(text) return #text * 6 end

	check("the first wording that fits wins, so the longest is kept when it fits", fit({ "Gathering Idols in the Barrens", "Gathering Idols" }, 200, width) == "Gathering Idols in the Barrens")
	check("a shorter wording is taken when the longer does not fit", fit({ "Gathering Idols in the Barrens", "Gathering Idols" }, 100, width) == "Gathering Idols")
	check("a plain string is one wording", fit("Gathering Idols", 200, width) == "Gathering Idols")
	check("with nothing that fits, the last wording is cut at a word", fit({ "Gathering Idols in the Barrens", "Gathering Idols of Kolkar" }, 110, width) == "Gathering Idols...")
	check("it never cuts inside a word", (function()
		for room = 0, 200, 3 do
			local text = fit("Gathering Idols of Kolkar", room, width)
			local body = text:gsub("%.%.%.$", "")
			local ok = body == "" or ("Gathering Idols of Kolkar"):sub(1, #body) == body and (("Gathering Idols of Kolkar"):sub(#body + 1, #body + 1) == " " or #body == #"Gathering Idols of Kolkar")
			if body:sub(-1) == " " then ok = false end
			if not ok then return false end
		end
		return true
	end)())
	check("a room that holds only the dots gets the dots, and less gets nothing", fit("Gathering Idols", 18, width) == "..." and fit("Gathering Idols", 10, width) == "")
	check("no wording gives nothing", fit({}, 100, width) == "" and fit(nil, 100, width) == "")
	check("a one-word title too wide for its room is the dots, not half the word", fit("Gathering", 40, width) == "..." or fit("Gathering", 40, width) == "")

	local natural = Everlook.island_row.natural_width({ title = { "Longer wording", "Short" } }, function(text) return width(text) end, 14, 0)
	check("a row asks for the width of its longest wording", natural >= width("Longer wording"))
end
