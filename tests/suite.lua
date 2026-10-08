-- Finds an addon file in the addon folder that ships it. A Lua file named on
-- its own must be listed in that folder's TOC. Other files, such as an asset,
-- only have to be in a folder. A name that starts with a folder is used as is.
return function(root)
	local folders, where = {}, { sign_template = "Everlook" }
	local listing = assert(io.popen('ls "' .. root .. '"'))
	for folder in listing:lines() do
		if folder:match("^Everlook[%w_]*$") then
			folders[#folders + 1] = folder
			for line in io.lines(root .. "/" .. folder .. "/" .. folder .. ".toc") do
				local file = line:match("^([%w_]+)%.lua%s*$")
				if file then where[file] = folder end
			end
		end
	end
	listing:close()
	return function(name)
		local folder_name = name:match("^(Everlook[%w_]*)/")
		if folder_name then return root .. "/" .. name, folder_name end
		local lua = name:match("^([%w_]+)$") or name:match("^([%w_]+)%.lua$")
		if lua then
			local folder = assert(where[lua], "No addon TOC lists " .. lua .. ".lua")
			return root .. "/" .. folder .. "/" .. lua .. ".lua", folder
		end
		for _, folder in ipairs(folders) do
			local path = root .. "/" .. folder .. "/" .. name
			local handle = io.open(path, "r")
			if handle then
				handle:close()
				return path, folder
			end
		end
		error("No addon folder has " .. name)
	end
end
