local _, Everlook = ...

-- EverlookDB carries a schema number. Each step brings a file written by an earlier
-- version up to the next number, in order, and a step is only ever added at the end.
-- A file with a higher number than this version knows was saved by a newer Everlook
-- and is left as it is.
Everlook.migrations = {}

local steps = {
	-- 1: settings hold only what a player changed. module.lua drops the values that
	-- equal a default when each module loads, so this step only makes sure the
	-- container is a table.
	function(db)
		if type(db.qol) ~= "table" then db.qol = {} end
	end,
}

Everlook.migrations.current = #steps

function Everlook.migrations.run(db)
	local from = db.schema
	if type(from) ~= "number" or from ~= from or from < 0 then from = 0 end
	if from > #steps then return from end
	for version = from + 1, #steps do
		steps[version](db)
		db.schema = version
	end
	return db.schema or from
end

-- Saved variables are in place when ADDON_LOADED fires for this addon, and the module
-- addons load after it, so they always see a migrated file.
if EventUtil and EventUtil.ContinueOnAddOnLoaded then
	EventUtil.ContinueOnAddOnLoaded("Everlook", function()
		EverlookDB = EverlookDB or {}
		Everlook.migrations.run(EverlookDB)
	end)
end
