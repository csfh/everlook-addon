-- The ring of errors Everlook caught.
return function(root, check)
	local source = dofile(root .. "/tests/suite.lua")(root)
	local Everlook = {}
	local env = setmetatable({ time = function() return 77 end }, { __index = _G })
	env._G = env
	local chunk = assert(loadfile(source("errors")))
	setfenv(chunk, env)
	chunk("Everlook", Everlook)
	local errors = Everlook.errors

	check("an empty ring lists nothing", #errors.list() == 0 and errors.count() == 0)
	errors.note("bags", "boom")
	errors.note(42, { })
	local list = errors.list()
	check("an error keeps its owner, text and time", #list == 2 and list[1].owner == "bags" and list[1].message == "boom" and list[1].at == 77)
	check("anything but text is stored as text", type(list[2].message) == "string" and list[2].owner == "42")
	errors.note("long", string.rep("x", 1000))
	check("a long message is cut", #errors.list()[3].message == 300)
	errors.clear()
	for i = 1, 25 do errors.note("owner", "error " .. i) end
	list = errors.list()
	check("the ring holds the last twenty, newest last", #list == 20 and list[1].message == "error 6" and list[20].message == "error 25")
	check("the count keeps counting past the ring", errors.count() == 25)
end
