local _, Everlook = ...

-- A short ring of the errors Everlook itself caught: a module's event handler, a tooltip
-- callback, queued combat work. It holds strings only, never the game's whole error log, and
-- it is a place to look, not a replacement for the error handler: whoever catches an error
-- still passes it on to the game's handler.
Everlook.errors = {}
local MAX = 20
local MESSAGE_MAX = 300
local ring, next_slot, total = {}, 1, 0

function Everlook.errors.note(owner, message)
	if type(message) ~= "string" then message = tostring(message) end
	if #message > MESSAGE_MAX then message = message:sub(1, MESSAGE_MAX) end
	ring[next_slot] = { owner = tostring(owner), message = message, at = time and time() or 0 }
	next_slot = next_slot % MAX + 1
	total = total + 1
end

-- Newest last.
function Everlook.errors.list()
	local out = {}
	local count = math.min(total, MAX)
	local first = total > MAX and next_slot or 1
	for i = 0, count - 1 do
		out[#out + 1] = ring[(first - 1 + i) % MAX + 1]
	end
	return out
end

function Everlook.errors.count()
	return total
end

function Everlook.errors.clear()
	ring, next_slot, total = {}, 1, 0
end
