CONFIG = {
	base = {
		cflags = "",
		lflags = "",
		objdir = "obj/",
		bindir = "bin/",
	},
	buildtypes = {
		debug = {
			suffix = "d",
		},
		release = {
			suffix = "",
		},
	},
}

function merge(v, tbl, index)
	if type((tbl or {})[index]) == "string" then
		local merged = tbl[index]
		if merged:sub(0, 1) == " " then
			error("Merged variables should not start with spaces:" .. merged, 3)
		elseif merged:sub(-1) == " " then
			error("Merged variables should not end with spaces: " .. merged, 3)
		end

		-- By only space-separating flags, we allow custom directories.
		if index:sub(-5) == "flags" and v != "" and merged != "" then
			return (v .. " " .. merged)
		else
			return (v .. merged)
		end
	end
	return v
end

function CONFIG:branch(buildtype_filter, ...)
	local arg = { ... }
	local ret = {
		base = {},
		buildtypes = {},
		branch = CONFIG.branch,
	}
	for k, v in pairs(self.base) do
		for _, other in pairs(arg) do
			v = merge(v, other.base, k)
		end
		ret.base[k] = v
	end
	for buildtype, vars in pairs(self.buildtypes) do
		if (buildtype_filter == "") or (buildtype == buildtype_filter) then
			ret.buildtypes[buildtype] = {}
			for k, v in pairs(vars) do
				for _, other in pairs(arg) do
					v = merge(v, (other.buildtypes or {})[buildtype], k)
				end
				ret.buildtypes[buildtype][k] = v
			end
		end
	end
	return ret
end

-- Inspired by https://stackoverflow.com/a/1283608.
function table_merge(t1, t2)
	-- The caller expects [t1] to remain unmodified, so we create a shallow copy
	local ret = {}
	for k, v in pairs(t1) do
		ret[k] = v
	end
	setmetatable(ret, getmetatable(t1))

	for k, v in pairs(t2) do
		if type(v) == "table" then
			if type(ret[k] or false) == "table" then
				ret[k] = table_merge(ret[k] or {}, t2[k] or {})
			elseif type(v) != 'function' then
				ret[k] = v
			end
		elseif type(v) != 'function' then
			ret += v
		end
	end
	return ret
end

-- https://stackoverflow.com/a/49709999
function table_filter(tbl, patterns)
	for _, pattern in pairs(patterns) do
		local new_index = 1
		local size_orig = #tbl
		for old_index, v in ipairs(tbl) do
			if not string.match(v, pattern) then
				tbl[new_index] = v
				new_index = new_index + 1
			end
		end
		for i = new_index, size_orig do tbl[i] = nil end
	end
	return tbl
end

functional_metatable = {
	__add = table_merge,
	__sub = table_filter,
}

tup.include(string.format("Tuprules.%s.lua", tup.getconfig("TUP_PLATFORM")))
