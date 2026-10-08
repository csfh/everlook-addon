local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "tooltip_cursor"
local hooked = false

-- The game places the default tooltip by calling GameTooltip_SetDefaultAnchor,
-- for units in the world and for most frames. One hook on that call moves
-- them all. Re-owning the tooltip with the cursor anchor makes it follow the
-- mouse, which is what the stock option for it does too. The offset keeps the
-- corner of the tooltip off the pointer. SetOwner's ofstx and ofsty are
-- interface coordinates from that anchor.
local CURSOR_X, CURSOR_Y = 16, 16

local function follow_cursor(tooltip, parent)
	if not module.enabled(id) or tooltip ~= GameTooltip then
		return
	end
	tooltip:SetOwner(parent, "ANCHOR_CURSOR", CURSOR_X, CURSOR_Y)
end

local function apply(enabled)
	if not enabled or hooked then
		return
	end
	if type(hooksecurefunc) ~= "function" or type(GameTooltip_SetDefaultAnchor) ~= "function" or not GameTooltip then
		return
	end
	hooksecurefunc("GameTooltip_SetDefaultAnchor", follow_cursor)
	hooked = true
end

module.register({
	addon = addon_name, page = "tooltips", order = 30,
	id = id,
	name = "Tooltip at cursor",
	description = "When the game places its default tooltip, this moves that tooltip just off the mouse cursor, so the pointer stays visible, and it follows the cursor. A tooltip already on screen stays until the next one is placed, a tooltip that is not the game's default stays where it is, turning this off puts the next one back where the game places it, and nothing happens when the client has no way to move it.",
	apply = apply,
})
