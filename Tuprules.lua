---@generic T
---@alias ConfigVarFunction fun(prev: T): T
---@alias ConfigVar T | ConfigVarFunction<T>

---@class ConfigBase
---@field cflags? ConfigVar<string[]>
---@field lflags? ConfigVar<string[]>
---@field objdir? ConfigVar<string>
---@field bindir? ConfigVar<string>
---@field coutputs? string[]
---@field loutputs? string[]

---@class ConfigBuildtype : ConfigBase
---@field suffix? ConfigVar<string>

---@alias ConfigBuildtypes { [string]: ConfigBuildtype }

---@class ConfigShape
---@field base? ConfigBase
---@field buildtypes? ConfigBuildtypes

---@class Config
CONFIG = {
	base = {
		cflags = {},
		lflags = {},
		objdir = "obj/",
		bindir = "bin/",
		coutputs = {},
		loutputs = {},
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
CONFIG.__index = CONFIG

---@generic T
---@param func fun(value: T)
---@param ... T[]
function ForEach(func, ...)
	local args = { ... }
	for _, arg in ipairs(args) do
		for _, value in ipairs(arg) do
			func(value)
		end
	end
end

---@param flag string
---@return ConfigVarFunction<string[]>
function flag_remove(flag)
	return function(prev)
		for i, prev_flag in ipairs(prev) do
			if (prev_flag == flag) then
				table.remove(prev, i)
			end
		end
		return prev
	end
end

---@return any merged Clone of `v` with `other` merged into it.
function Merge(v, other)
	local v_type = type(v)
	local other_type = type(other)
	if (other_type == "string") then
		if other:sub(0, 1) == " " then
			error("Merged variables should not start with spaces:" .. other, 3)
		elseif other:sub(-1) == " " then
			error("Merged variables should not end with spaces: " .. other, 3)
		end
		return (v .. other)
	elseif (other_type == "table") then
		local ret = { table.unpack(v) }	-- Create a shallow copy
		for key, value in pairs(other) do
			table.insert(v, key, value)
		end
		return ret
	elseif ((v_type == "table") and (other_type == "function")) then
		return other({ table.unpack(v) })
	end
	error(string.format(
		"No merging rule defined for %s←%s", v_type, other_type
	))
end

---@param ... ConfigShape
---@return Config
function CONFIG:branch(...)
	local arg = { ... }

	---@class Config
	local ret = setmetatable({ base = {}, buildtypes = {} }, self)
	ret.__index = self

	for k, v in pairs(self.base) do
		for _, other in pairs(arg) do
			---@cast other +Config
			if other.branch then
				error(
					"Configurations should not be combined with each other", 2
				)
			end
			v = Merge(v, (other.base or {})[k])
		end
		ret.base[k] = v
	end
	for buildtype, vars in pairs(self.buildtypes) do
		ret.buildtypes[buildtype] = {}
		for k, v in pairs(vars) do
			for _, other in pairs(arg) do
				v = Merge(v, ((other.buildtypes or {})[buildtype] or {})[k])
			end
			ret.buildtypes[buildtype][k] = v
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
			elseif (type(v) ~= 'function') then
				ret[k] = v
			end
		elseif (type(v) ~= 'function') then
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

function sourcepath(path)
	if (path:sub(-1) ~= "/") then
		error("Paths should end with a slash: " .. path, 2)
	end
	return {
		root = path,
		join = function(component)
			return (path .. component)
		end,
		glob = function(pattern)
			local ret = tup.glob(path .. pattern)
			setmetatable(ret, functional_metatable)
			return ret
		end
	}
end

---Concatenates `flags` with a leading whitespace if not empty.
---@param ... string[]
function ConcatFlags(...)
	local ret = ""
	ForEach(function (flag)
		ret = (ret .. " " .. flag)
	end, ...)
	return ret
end

tup.include(string.format("Tuprules.%s.lua", tup.getconfig("TUP_PLATFORM")))
