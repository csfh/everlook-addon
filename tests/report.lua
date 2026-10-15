-- /everlook report: what is saved, what is cut, and what is kept.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local function load(clock)
		local said = {}
		local Everlook = { say = function(line) said[#said + 1] = line end }
		local env = setmetatable({ EverlookDB = {}, time = function() return clock.now end }, { __index = _G })
		env._G = env
		for _, name in ipairs({ "hash", "errors", "where", "report" }) do
			local chunk = assert(loadfile(source(name)))
			setfenv(chunk, env)
			chunk("Everlook", Everlook)
		end
		Everlook.module = { modules = {}, enabled = function() return false end }
		return Everlook, env, said
	end

	local clock = { now = 1760000000 }
	local addon, env, said = load(clock)
	check("a limit of three characters keeps three, not a broken one", addon.report.cut("ab\195\169cd", 3) == "ab\195\169" and addon.report.cut("ab\195\169cd", 2) == "ab")
	check("a four byte character is kept whole or dropped whole", addon.report.cut("a\240\159\152\128b", 2) == "a\240\159\152\128" and addon.report.cut("a\240\159\152\128b", 1) == "a")
	check("a short text is left as it is", addon.report.cut("hello", 10) == "hello" and addon.report.cut(nil, 10) == "")

	check("no words saves nothing and says how to write one", addon.report.add("   ") == nil and (function() addon.report.command(nil); return said[#said]:find("Write what went wrong", 1, true) ~= nil end)())
	local report = addon.report.add("  The vendor\nsells nothing.  ")
	check("a report keeps the words on one line with an id and a time", report.text == "The vendor sells nothing." and #report.id == 8 and report.at == clock.now and env.EverlookDB.reports[1] == report)
	check("the facts say the install and are text", type(report.facts) == "string")

	local long = string.rep("\195\169", 1500)
	check("the words are cut to 1000 characters", #addon.report.add(long).text == 2000)

	addon.errors.note("Bags", string.rep("x", 400))
	local facts = addon.report.facts()
	check("an error line is cut to 200 characters after its label", facts:find("Error from Bags: ", 1, true) and #facts:match("Error from Bags: (x+)") == 200)

	for index = 1, 7 do
		clock.now = clock.now + 60
		addon.report.add("report " .. index)
	end
	local list = env.EverlookDB.reports
	check("only the five newest are kept", #list == 5 and list[1].text == "report 3" and list[5].text == "report 7")
	clock.now = clock.now + 15 * 24 * 3600
	addon.report.add("fresh")
	check("a report older than fourteen days is dropped", #env.EverlookDB.reports == 1 and env.EverlookDB.reports[1].text == "fresh")
	check("the ids differ", (function() local a = addon.report.add("same words"); clock.now = clock.now + 1; local b = addon.report.add("same words"); return a.id ~= b.id end)())
end
