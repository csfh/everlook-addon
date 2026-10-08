local Everlook = Everlook

-- Which notice gets a toast slot first. Warnings beat routine notices and
-- errors beat warnings. smart_island.lua owns the stack and its frames.
local toasts = {}
Everlook.island_toasts = toasts

function toasts.priority(entry)
	return entry.severity == "error" and 3 or entry.severity == "warning" and 2 or 1
end

-- The waiting notice that should show next. Ties go to the earliest.
function toasts.next_index(queue)
	local chosen = 1
	for index = 2, #queue do
		if toasts.priority(queue[index]) > toasts.priority(queue[chosen]) then chosen = index end
	end
	return chosen
end

-- The first waiting notice that a newcomer outranks, or nil when none is lower.
function toasts.evict_index(queue, entry)
	for index, waiting in ipairs(queue) do
		if toasts.priority(waiting) < toasts.priority(entry) then return index end
	end
end
