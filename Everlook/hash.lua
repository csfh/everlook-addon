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

-- These carry the portable path and the key padding. They never use the bit
-- library, so a library that misbehaves cannot reach the fallback.
local bxor = xor_lua
local function band(left, right)
	return ((left % modulus) + (right % modulus) - xor_lua(left, right)) / 2
end
local function bnot(value)
	return modulus - 1 - value % modulus
end
local function rshift(value, count)
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

local function initial_state()
	return { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
end

local words = {}

-- Without a bit library the arithmetic helpers above carry the work.
local function compress_portable(state, text, first, last)
	for offset = first, last, 64 do
		for index = 1, 16 do
			local a, b, c, d = text:byte(offset + (index - 1) * 4, offset + index * 4 - 1)
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
			local first_sum = (h + sigma1 + choice + constants[index] + words[index]) % modulus
			local sigma0 = bxor(bxor(rotate(a, 2), rotate(a, 13)), rotate(a, 22))
			local majority = bxor(bxor(band(a, b), band(a, c)), band(b, c))
			local second_sum = (sigma0 + majority) % modulus
			h, g, f, e, d, c, b, a = g, f, e, (d + first_sum) % modulus, c, b, a, (first_sum + second_sum) % modulus
		end
		local compressed = { a, b, c, d, e, f, g, h }
		for index = 1, 8 do
			state[index] = (state[index] + compressed[index]) % modulus
		end
	end
end

-- With a bit library every rotate is two shifts and an or, and the sums stay
-- in doubles until a round ends. Only the two-argument form of each function
-- is used, and only the ones Blizzard's own code calls.
local compress = compress_portable

if native and native.bxor and native.band and native.bor and native.bnot and native.lshift and native.rshift then
	local nxor, nand, nor, nnot, nshl, nshr = native.bxor, native.band, native.bor, native.bnot, native.lshift, native.rshift
	local byte = string.byte
	compress = function(state, text, first, last)
		local w = words
		local k = constants
		for offset = first, last, 64 do
			for index = 0, 15 do
				local at = offset + index * 4
				local b1, b2, b3, b4 = byte(text, at, at + 3)
				w[index + 1] = b1 * 16777216 + b2 * 65536 + b3 * 256 + b4
			end
			for index = 17, 64 do
				local left, right = w[index - 15], w[index - 2]
				local sigma0 = nxor(nxor(nor(nshr(left, 7), nshl(left, 25)), nor(nshr(left, 18), nshl(left, 14))), nshr(left, 3))
				local sigma1 = nxor(nxor(nor(nshr(right, 17), nshl(right, 15)), nor(nshr(right, 19), nshl(right, 13))), nshr(right, 10))
				w[index] = (w[index - 16] + sigma0 + w[index - 7] + sigma1) % modulus
			end
			local a, b, c, d, e, f, g, h = state[1], state[2], state[3], state[4], state[5], state[6], state[7], state[8]
			for index = 1, 64 do
				local sigma1 = nxor(nxor(nor(nshr(e, 6), nshl(e, 26)), nor(nshr(e, 11), nshl(e, 21))), nor(nshr(e, 25), nshl(e, 7)))
				local choice = nxor(g, nand(e, nxor(f, g)))
				local first_sum = h + sigma1 + choice + k[index] + w[index]
				local sigma0 = nxor(nxor(nor(nshr(a, 2), nshl(a, 30)), nor(nshr(a, 13), nshl(a, 19))), nor(nshr(a, 22), nshl(a, 10)))
				local ab = nor(a, b)
				local majority = nor(nand(a, b), nand(c, ab))
				h, g, f, e, d, c, b, a = g, f, e, (d + first_sum) % modulus, c, b, a, (first_sum + sigma0 + majority) % modulus
			end
			state[1] = (state[1] + a) % modulus
			state[2] = (state[2] + b) % modulus
			state[3] = (state[3] + c) % modulus
			state[4] = (state[4] + d) % modulus
			state[5] = (state[5] + e) % modulus
			state[6] = (state[6] + f) % modulus
			state[7] = (state[7] + g) % modulus
			state[8] = (state[8] + h) % modulus
		end
	end
end

-- The fast path is trusted only after it hashes "abc" correctly. A bit library
-- that rounds, wraps or signs differently would otherwise make every signature
-- wrong, and nothing in game would show it.
if compress ~= compress_portable then
	local state = initial_state()
	compress(state, "abc\128" .. string.rep("\0", 52) .. "\0\0\0\0\0\0\0\24", 1, 64)
	if state[1] ~= 0xba7816bf or state[2] ~= 0x8f01cfea or state[5] ~= 0xf61f2001 or state[8] ~= 0xf20015ad then
		compress = compress_portable
	end
end

-- Whole blocks are read in place. Only the tail is copied to be padded, so a
-- large message is never copied to be hashed. `prefix` counts bytes already
-- fed to the state, as when HMAC feeds its key block first.
local function finish(state, message, prefix)
	local length = #message
	local whole = length - length % 64
	if whole > 0 then
		compress(state, message, 1, whole - 63)
	end
	local bits = (prefix + length) * 8
	local tail = message:sub(whole + 1) .. "\128" .. string.rep("\0", (55 - length) % 64)
		.. word_bytes(floor(bits / modulus)) .. word_bytes(bits)
	compress(state, tail, 1, #tail - 63)
	local digest = {}
	for index = 1, 8 do
		digest[index] = word_bytes(state[index])
	end
	return table.concat(digest)
end

local function sha256_bytes(message)
	return finish(initial_state(), message, 0)
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
	local state = initial_state()
	compress(state, table.concat(inner), 1, 1)
	local inner_digest = finish(state, message, 64)
	return hex(sha256_bytes(table.concat(outer) .. inner_digest))
end
