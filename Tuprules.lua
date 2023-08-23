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

tup.include(string.format("Tuprules.%s.lua", tup.getconfig("TUP_PLATFORM")))
