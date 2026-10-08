local addon_name = ...
local Everlook = Everlook
local module = Everlook.module
local id = "auto_repair"
local pending, merchant_open
local next_result = 0

local function readable(value)
	return not (issecretvalue and issecretvalue(value)) and value ~= nil
end

local function amount(value)
	return readable(value) and type(value) == "number" and value == value and value >= 0 and value < math.huge
end

local function island_enabled()
	return Everlook.island and type(Everlook.island.notify) == "function" and module.enabled("smart_island") and module.get("smart_island", "source_repair")
end

local function notice(payload)
	if not island_enabled() then return end
	next_result = next_result + 1
	payload.source, payload.key, payload.kind, payload.stack = "everlook.auto_repair", "repair:" .. next_result, "repair", "repair"
	-- A display failure must not change the result of the repair itself.
	local ok, result = pcall(Everlook.island.notify, payload)
	if not ok and geterrorhandler then geterrorhandler()(type(result) == "string" and result or "Everlook repair notice failed") end
	return ok and type(result) == "number"
end

local function observe(cost, guild)
	pending = nil
	if not island_enabled() or not C_Timer or not C_Timer.After then return end
	local token = { cost = cost, guild = guild }
	pending = token
	C_Timer.After(3, function() if pending == token then pending = nil end end)
end

local function confirm()
	if not pending or not merchant_open or not island_enabled() or not GetRepairAllCost then return end
	local cost, needed = GetRepairAllCost()
	if not amount(cost) or not readable(needed) or type(needed) ~= "boolean" or cost ~= 0 or needed then
		local token = pending
		if not token.retrying then
			token.retrying = true
			C_Timer.After(0.1, function()
				if pending ~= token then return end
				token.retrying = nil
				confirm()
			end)
		end
		return
	end
	local result = pending
	pending = nil
	notice({ text = "Equipment repaired", severity = "success", money = -result.cost,
		detail = result.guild and "Paid from guild funds" or "Paid from personal funds" })
end

local function repair()
	pending = nil
	if module.paused() or not CanMerchantRepair or not CanMerchantRepair() or not GetRepairAllCost or not RepairAllItems then return end
	local cost, needed = GetRepairAllCost()
	if not amount(cost) or cost <= 0 or not readable(needed) or needed ~= true then return end
	if module.get(id, "guild_funds") and CanGuildBankRepair and CanGuildBankRepair() and GetGuildBankWithdrawMoney and GetGuildBankMoney then
		local allowance, funds = GetGuildBankWithdrawMoney(), GetGuildBankMoney()
		if readable(allowance) and type(allowance) == "number" and amount(funds)
			and (allowance == -1 or allowance >= cost) and funds >= cost then
			observe(cost, true)
			RepairAllItems(true)
			return
		end
	end
	local funds = GetMoney and GetMoney()
	if not amount(funds) then return end
	if funds >= cost then
		observe(cost, false)
		RepairAllItems(false)
	else
		if Everlook.say then Everlook.say("Not enough gold to repair your gear.") end
		notice({ text = "Not enough gold to repair", detail = "Personal funds are below the repair cost", severity = "warning" })
	end
end

module.register({
	addon = addon_name, page = "vendors", order = 20,
	id = id, name = "Auto repair", description = "Repairs your gear when a repair vendor opens and something needs repair. Turning this on while that window is already open waits for the next one, holding Shift pauses it, gear that does not need repair and a vendor who cannot repair are left alone, a cost or a gold amount the client hides stays quiet, when the repair would come from your own gold and that gold is short the gear stays and it says you do not have enough gold to repair, and turning this off leaves the next vendor.",
	options = { guild_funds = { name = "Use guild funds first", default = false, description = "Pays the repair from the guild bank when you are allowed to, and your withdraw allowance and the bank both cover the cost. Otherwise, or with this off, your own gold pays, and when that gold is short the gear stays and it says you do not have enough gold to repair." } },
	apply = function(enabled) if not enabled then pending, merchant_open = nil, nil end end,
	events = { "MERCHANT_SHOW", "MERCHANT_CLOSED", "UPDATE_INVENTORY_DURABILITY" },
	on_event = function(event)
		if event == "MERCHANT_SHOW" then merchant_open = true; repair()
		elseif event == "MERCHANT_CLOSED" then pending, merchant_open = nil, nil
		else confirm() end
	end,
})
