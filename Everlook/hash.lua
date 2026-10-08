local _, Everlook = ...

local floor = math.floor
local modulus = 4294967296
local native = _G.bit or _G.bit32

-- Plain Lua 5.1 has no bit library. WoW provides bit or bit32; the
-- arithmetic path also allows the same implementation to run in CLI tests.
local xor_digits = {}
for left = 0, 15 do
	xor_digits[left] = {}
	for right = 0, 15 do
		local a, b, value, place = left, right, 0, 1
		for index = 1, 4 do
			value = value + ((a % 2 + b % 2) % 2) * place
			a, b, place = floor(a / 2), floor(b / 2), place * 2
		end
		xor_digits[left][right] = value
	end
end

local function xor_lua(left, right)
	local a, b, value, place = left % modulus, right % modulus, 0, 1
	while a > 0 or b > 0 do
		value = value + xor_digits[a % 16][b % 16] * place
		a, b, place = floor(a / 16), floor(b / 16), place * 16
	end
	return value
end

local bxor = native and native.bxor or xor_lua
local band = native and native.band or function(left, right)
	return ((left % modulus) + (right % modulus) - xor_lua(left, right)) / 2
end
local bnot = native and native.bnot or function(value)
	return modulus - 1 - value % modulus
end
local rshift = native and native.rshift or function(value, count)
	return floor((value % modulus) / 2 ^ count)
end

local function rotate(value, count)
	value = value % modulus
	return floor(value / 2 ^ count) + (value % 2 ^ count) * 2 ^ (32 - count)
end

-- SHA-256 constants and compression from FIPS 180-4, sections 4.2.2 and 6.2.
local constants = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

local function word_bytes(value)
	value = value % modulus
	return string.char(floor(value / 16777216), floor(value / 65536) % 256, floor(value / 256) % 256, value % 256)
end

local function sha256_bytes(message)
	local length = #message * 8
	local padded = message .. "\128" .. string.rep("\0", (55 - #message) % 64)
		.. word_bytes(floor(length / modulus)) .. word_bytes(length)
	local state = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
	local words = {}
	for offset = 1, #padded, 64 do
		for index = 1, 16 do
			local a, b, c, d = padded:byte(offset + (index - 1) * 4, offset + index * 4 - 1)
			words[index] = a * 16777216 + b * 65536 + c * 256 + d
		end
		for index = 17, 64 do
			local left, right = words[index - 15], words[index - 2]
			local sigma0 = bxor(bxor(rotate(left, 7), rotate(left, 18)), rshift(left, 3))
			local sigma1 = bxor(bxor(rotate(right, 17), rotate(right, 19)), rshift(right, 10))
			words[index] = (words[index - 16] + sigma0 + words[index - 7] + sigma1) % modulus
		end
		local a, b, c, d, e, f, g, h = unpack(state)
		for index = 1, 64 do
			local sigma1 = bxor(bxor(rotate(e, 6), rotate(e, 11)), rotate(e, 25))
			local choice = bxor(band(e, f), band(bnot(e), g))
			local first = (h + sigma1 + choice + constants[index] + words[index]) % modulus
			local sigma0 = bxor(bxor(rotate(a, 2), rotate(a, 13)), rotate(a, 22))
			local majority = bxor(bxor(band(a, b), band(a, c)), band(b, c))
			local second = (sigma0 + majority) % modulus
			h, g, f, e, d, c, b, a = g, f, e, (d + first) % modulus, c, b, a, (first + second) % modulus
		end
		local compressed = { a, b, c, d, e, f, g, h }
		for index = 1, 8 do
			state[index] = (state[index] + compressed[index]) % modulus
		end
	end
	local digest = {}
	for index = 1, 8 do
		digest[index] = word_bytes(state[index])
	end
	return table.concat(digest)
end

local function hex(bytes)
	return (bytes:gsub(".", function(byte)
		return string.format("%02x", byte:byte())
	end))
end

Everlook.hash = {}

function Everlook.hash.sha256(message)
	return hex(sha256_bytes(message))
end

function Everlook.hash.hmac_sha256(key, message)
	if #key > 64 then
		key = sha256_bytes(key)
	end
	key = key .. string.rep("\0", 64 - #key)
	local inner, outer = {}, {}
	for index = 1, 64 do
		inner[index] = string.char(bxor(key:byte(index), 0x36))
		outer[index] = string.char(bxor(key:byte(index), 0x5c))
	end
	return hex(sha256_bytes(table.concat(outer) .. sha256_bytes(table.concat(inner) .. message)))
end
