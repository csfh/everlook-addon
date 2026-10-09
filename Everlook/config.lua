local _, Everlook = ...

Everlook.config = Everlook.config or {}

local function saved()
	_G.EverlookDB = _G.EverlookDB or {}
	return _G.EverlookDB
end

-- The sign.lua token wins so a token the app places again replaces a stale
-- one. The saved copy of the last token is the fallback if sign.lua loses it.
local function secret_value()
	local db = saved()
	local token = Everlook.config.token
	if type(token) == "string" and token ~= "" then
		db.secret = token
		return token
	end
	local saved_secret = db.secret
	if type(saved_secret) == "string" and saved_secret ~= "" then
		return saved_secret
	end
end

local signer_secret, signer_value

-- The server's short name for a token. The tooltip asks for it on every hover,
-- so the hash is kept for the token it was made from.
local function signer_for(secret)
	if signer_secret ~= secret then
		signer_secret = secret
		signer_value = Everlook.hash.sha256(secret):sub(1, 16)
	end
	return signer_value
end

-- The token and the short name the server knows it by, without signing
-- anything. Nil until a token is placed.
function Everlook.config.credentials()
	local secret = secret_value()
	if type(secret) ~= "string" or secret == "" then
		return nil
	end
	return secret, signer_for(secret)
end

function Everlook.config.sign(payload)
	local db = saved()
	local secret = secret_value()
	db.signer = nil
	db.signature = nil
	if type(payload) ~= "string" or payload == "" or type(secret) ~= "string" or secret == "" then
		return
	end
	db.signer = signer_for(secret)
	db.signature = Everlook.hash.hmac_sha256(secret, payload)
end

-- Saves are signed at logout, so the signature on file is the one the last
-- session left. It counts when it was made with the token in use now.
local function signed_with(secret)
	local db = saved()
	return type(db.signature) == "string" and db.signature ~= "" and db.signer == signer_for(secret)
end

-- One of "no_token", "pending" (a secret is set and the save on file was not
-- signed with it yet), or "signed".
function Everlook.config.status()
	local secret = secret_value()
	if type(secret) ~= "string" or secret == "" then
		return "no_token"
	end
	if signed_with(secret) then
		return "signed"
	end
	return "pending"
end

-- The first 8 characters of the signer, the same short code the Everlook app
-- and site show. Nil until a save has been signed with the current token.
function Everlook.config.fingerprint()
	if Everlook.config.status() == "signed" then
		return saved().signer:sub(1, 8)
	end
end

-- Status text with a color, shared by the minimap tooltip and the load line.
function Everlook.config.describe()
	local status = Everlook.config.status()
	if status == "signed" then
		return status, "Signed \194\183 " .. (Everlook.config.fingerprint() or ""), 0.3, 0.9, 0.4
	elseif status == "pending" then
		local code = signer_for(secret_value()):sub(1, 8)
		return status, "Token " .. code .. " loaded. Saves are signed as you play, and when you log out or reload.", 1, 0.82, 0.2
	end
	return status, "Not signed. Place the token in the Everlook app.", 1, 0.3, 0.3
end
