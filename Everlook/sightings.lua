local _, Everlook = ...

Everlook.sightings = {}

-- A secret guid has type "string". Comparing it, or using it as a key, errors.
function Everlook.sightings.plain_guid(guid)
	return Everlook.world.usable(guid) and type(guid) == "string"
end

-- One sighting per guid and source inside the window keeps a row current
-- without rebuilding the world document. Each collector keeps its own window,
-- so a creature guid that the object watcher set aside does not hide the npc.
function Everlook.sightings.window(seconds)
	local window = type(seconds) == "number" and seconds or 5
	local seen_at = {}
	local next_sweep = 0
	local sightings = {}

	function sightings.same(guid, source)
		if not Everlook.sightings.plain_guid(guid) or type(GetTime) ~= "function" then
			return false
		end
		local now = GetTime()
		local by_source = seen_at[guid]
		local previous = by_source and by_source[source]
		if type(now) ~= "number" or type(previous) ~= "number" then
			return false
		end
		return (now - previous) < window
	end

	function sightings.note(guid, source)
		if not Everlook.sightings.plain_guid(guid) or type(GetTime) ~= "function" then
			return
		end
		local now = GetTime()
		if type(now) ~= "number" then
			return
		end
		local by_source = seen_at[guid]
		if not by_source then
			by_source = {}
			seen_at[guid] = by_source
		end
		by_source[source] = now
		if now < next_sweep then
			return
		end
		next_sweep = now + window
		for seen_guid, sources in pairs(seen_at) do
			for seen_source, at in pairs(sources) do
				if (now - at) >= window then
					sources[seen_source] = nil
				end
			end
			if not next(sources) then
				seen_at[seen_guid] = nil
			end
		end
	end

	return sightings
end
