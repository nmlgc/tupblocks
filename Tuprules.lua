CONFIG = {
	buildtypes = {
		debug = {
			objdir = "Debug/",
			suffix = "d",
		},
		release = {
			objdir = "Release/",
			suffix = "",
		},
	},
}

function merge(v, tbl, index)
	if type((tbl or {})[index]) == "string" then
		return (v .. tbl[index])
	end
	return v
end

function CONFIG:branch(buildtype_filter, ...)
	local arg = { ... }
	local ret = {
		buildtypes = {},
		branch = CONFIG.branch,
	}
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
