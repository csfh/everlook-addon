local addon_name = ...
local Everlook = Everlook
local plates = Everlook.nameplates
local plain = plates.plain

-- Temporary: /everlookplates writes down what each visible nameplate is made of in this client, to read after a reload.
-- Nameplates are built by the game's own code, which differs between clients, so what a plate holds is looked up here
-- and not assumed. Every read is guarded because some regions refuse to be measured.
SLASH_EVERLOOKPLATES1 = "/everlookplates"
SlashCmdList = SlashCmdList or {}
SlashCmdList.EVERLOOKPLATES = function()
	local function try(target, method, ...)
		if type(target) ~= "table" or type(target[method]) ~= "function" then return nil end
		local results = { pcall(target[method], target, ...) }
		if not results[1] then return nil end
		return unpack(results, 2)
	end
	local function text(value)
		if value == nil then return "nil" end
		if issecretvalue and issecretvalue(value) then return "<secret>" end
		return tostring(value)
	end
	local function anchor(region)
		local count = try(region, "GetNumPoints")
		if type(count) ~= "number" then return "points ?" end
		local parts = {}
		for index = 1, math.min(count, 3) do
			local point, relative, relative_point, x, y = try(region, "GetPoint", index)
			local relative_name = relative and (try(relative, "GetDebugName") or try(relative, "GetName")) or "none"
			parts[#parts + 1] = text(point) .. ">" .. text(relative_name) .. ":" .. text(relative_point) .. " " .. text(x) .. "," .. text(y)
		end
		return "points " .. count .. " [" .. table.concat(parts, "; ") .. "]"
	end
	local function describe(key, value)
		local kind = try(value, "GetObjectType")
		if type(kind) ~= "string" then return key .. " = " .. type(value) end
		local line = key .. " = " .. kind .. " shown=" .. text(try(value, "IsShown")) .. " alpha=" .. text(try(value, "GetAlpha")) .. " " .. anchor(value)
		local width, height = try(value, "GetWidth"), try(value, "GetHeight")
		line = line .. " size " .. text(width) .. "x" .. text(height)
		if kind == "FontString" then
			local font, size = try(value, "GetFont")
			line = line .. " text=" .. text(try(value, "GetText")) .. " font=" .. text(font) .. " " .. text(size) .. " justify=" .. text(try(value, "GetJustifyH"))
		elseif kind == "Texture" then
			line = line .. " atlas=" .. text(try(value, "GetAtlas")) .. " file=" .. text(try(value, "GetTexture"))
		end
		return line
	end
	local lines = {}
	local function say(line) lines[#lines + 1] = line end
	for _, cvar in ipairs({ "nameplateShowFriends", "nameplateShowFriendlyNpcs", "nameplateShowEnemies", "nameplateShowAll", "nameplateStyle", "nameplateSize", "nameplateSimplifiedTypes", "nameplateShowOnlyNameForFriendlyPlayerUnits", "UnitNameNPC", "UnitNameFriendlySpecialNPCName", "nameplateMotion", "nameplateMotionSpeed", "nameplateOverlapH", "nameplateOverlapV" }) do
		local ok, value = pcall(GetCVar, cvar)
		say("cvar " .. cvar .. " = " .. (ok and text(value) or "none"))
	end
	if not (C_NamePlate and C_NamePlate.GetNamePlates) then
		say("no C_NamePlate.GetNamePlates")
	else
		for _, plate in ipairs(C_NamePlate.GetNamePlates()) do
			local unit = plates.unit_of(plate)
			say("== " .. text(unit) .. " forbidden=" .. text(try(plate, "IsForbidden")) .. " plate.GetUnit=" .. text(try(plate, "GetUnit")) .. " unitToken=" .. text(plate.unitToken) .. " namePlateUnitToken=" .. text(plate.namePlateUnitToken) .. " UnitFrame.unit=" .. text(plate.UnitFrame and plate.UnitFrame.unit))
			if type(unit) == "string" then
				say("unit: exists=" .. text(UnitExists and UnitExists(unit)) .. " player=" .. text(UnitIsPlayer and UnitIsPlayer(unit)) .. " canattack=" .. text(UnitCanAttack and UnitCanAttack("player", unit))
					.. " friend=" .. text(UnitIsFriend and UnitIsFriend("player", unit)) .. " classification=" .. text(UnitClassification and UnitClassification(unit)) .. " level=" .. text(UnitLevel and UnitLevel(unit)))
			end
			say(describe("plate", plate))
			local frame = plate.UnitFrame
			if not frame then
				say("no UnitFrame")
			else
				say(describe("UnitFrame", frame))
				local methods = {}
				for _, method in ipairs({ "IsShowOnlyName", "IsSimplified", "IsFriend", "IsPlayer", "IsMinion", "IsMinusMob", "IsTarget", "IsFocus", "IsDead" }) do
					methods[#methods + 1] = method .. "=" .. (type(frame[method]) == "function" and text(try(frame, method)) or "none")
				end
				say("flags " .. table.concat(methods, " "))
				say("widgetsOnlyMode=" .. text(frame.widgetsOnlyMode) .. " showOnlyName=" .. text(frame.showOnlyName) .. " isSimplified=" .. text(frame.isSimplified) .. " disableMouse=" .. text(frame.disableMouse))
				local keys = {}
				for key in pairs(frame) do keys[#keys + 1] = tostring(key) end
				table.sort(keys)
				for _, key in ipairs(keys) do
					local value = frame[key]
					if type(value) == "table" then
						say("  " .. describe(key, value))
						-- One level down, for the frames that hold the health bar and the rest.
						if try(value, "GetObjectType") == "Frame" or try(value, "GetObjectType") == "StatusBar" or try(value, "GetObjectType") == "Button" then
							local children = {}
							for child_key, child in pairs(value) do
								if type(child) == "table" and try(child, "GetObjectType") then children[#children + 1] = tostring(child_key) end
							end
							table.sort(children)
							for _, child_key in ipairs(children) do say("    " .. describe(key .. "." .. child_key, value[child_key])) end
						end
					end
				end
			end
		end
	end
	EverlookDB = EverlookDB or {}
	EverlookDB.plate_anatomy = { when = date and date("%Y-%m-%d %H:%M:%S") or "?", lines = lines }
	print("Everlook plates: wrote " .. #lines .. " lines; type /reload to save them to disk")
end
