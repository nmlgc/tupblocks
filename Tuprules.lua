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

---Deep-clones both the array and associative parts of `table`.
---@param table table
local function table_clone(table)
	local ret = {}
	for key, value in pairs(table) do
		if ((type(value) == "table") and (key ~= "__index")) then
			ret[key] = table_clone(value)
		else
			ret[key] = value
		end
	end
	return ret
end

---Extends `t` in-place with the contents of `other`. Returns `table`.
---@param t table
---@param other any
function TableExtend(t, other)
	if (other == nil) then
		return t
	end
	local other_type = type(other)
	if (other_type == "table") then
		t += other -- Append the array part via Tup's faster C extension
		for k, o in pairs(other) do -- Merge the associative part
			if (type(k) == "string") then
				local tk_type = type(t[k])
				local o_type = type(o)
				if ((tk_type == "table") or (o_type == "table")) then
					t[k] = TableExtend((t[k] or {}), o)
				end
			end
		end
	elseif (other_type == "string") then
		table.insert(t, other)
	elseif (other_type == "function") then
		return other(t)
	end
	return t
end

---@return any merged Clone of `v` with `other` merged into it.
function Merge(v, other)
	local v_type = type(v)
	local other_type = type(other)
	if (v_type == "string") then
		if (other == nil) then
			return v
		end
		if other:sub(0, 1) == " " then
			error("Merged variables should not start with spaces:" .. other, 3)
		elseif other:sub(-1) == " " then
			error("Merged variables should not end with spaces: " .. other, 3)
		end
		return (v .. other)
	elseif (v_type == "table") then
		return TableExtend(table_clone(v), other)
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

function table_merge(t1, t2)
	return setmetatable(TableExtend(table_clone(t1), t2), getmetatable(t1))
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
