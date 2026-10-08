local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "cinematic_skip"

local function cancel()
	if module.paused() then
		return
	end
	if type(CinematicFrame_CancelCinematic) == "function" then
		CinematicFrame_CancelCinematic()
		return
	end
	if type(MovieFrame_StopMovie) == "function" then
		MovieFrame_StopMovie()
		return
	end
	if type(CancelCinematic) == "function" then
		CancelCinematic()
	end
end

module.register({
	addon = addon_name, page = "interface", order = 80,
	id = id,
	name = "Cinematic skip",
	description = "Closes a cinematic or a movie when it starts. One already playing stays up, holding Shift leaves the new one playing, nothing happens when the client has no cancel function, and turning this off leaves the next one.",
	events = { "CINEMATIC_START", "PLAY_MOVIE" },
	on_event = function()
		cancel()
	end,
})
