local Everlook = Everlook

-- The Island's retained history: which notice goes when the inbox is full, how
-- many are unread, and how a cleared inbox merges back. All of it works on
-- plain arrays of notices, oldest first. smart_island.lua owns the list itself.
local inbox = {}
Everlook.island_inbox = inbox

function inbox.unread(notices)
	local count = 0
	for _, entry in ipairs(notices) do
		if entry.unread then count = count + 1 end
	end
	return count
end

-- Higher rank stays longer: a notice that needs a decision, then a warning,
-- then an unread one. The oldest of the lowest rank goes first.
local function rank(entry)
	local warning = entry.severity == "warning" or entry.severity == "error"
	return (entry.persist and 4 or 0) + (warning and 2 or 0) + (entry.unread and 1 or 0)
end

function inbox.evict(notices, limit)
	while #notices > limit do
		local chosen, lowest
		for index, entry in ipairs(notices) do
			local value = rank(entry)
			if not lowest or value < lowest then chosen, lowest = index, value end
		end
		table.remove(notices, chosen)
	end
end

local function already_present(notices, entry)
	for _, current in ipairs(notices) do
		if current.id == entry.id or (entry.key and current.source == entry.source and current.key == entry.key) then return true end
	end
	return false
end

-- Returns the cleared entries that a producer has not since replaced, merged
-- with the current ones in time order.
function inbox.restore(current, cleared)
	local merged = {}
	for _, entry in ipairs(cleared) do
		if not already_present(current, entry) then merged[#merged + 1] = entry end
	end
	for _, entry in ipairs(current) do merged[#merged + 1] = entry end
	table.sort(merged, function(a, b)
		if a.updated_at == b.updated_at then return a.id < b.id end
		return a.updated_at < b.updated_at
	end)
	return merged
end
