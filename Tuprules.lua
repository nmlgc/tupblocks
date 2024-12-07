---@generic T
---@alias ConfigVarFunction fun(prev: T): T
---@alias ConfigVar T | ConfigVarFunction<T>
---@alias ConfigVarBuildtyped { [integer]: ConfigVar, [string]: ConfigVar[] }

---@class ConfigShape
---@field objdir? ConfigVar<string>
---@field bindir? ConfigVar<string>
---@field suffix? ConfigVarBuildtyped<string>
---Flags added to the command line
---@field cflags? ConfigVarBuildtyped<string>
---@field lflags? ConfigVarBuildtyped<string>
---Inputs. `extra_inputs` are only supported at the buildtype level.
---@field cinputs? { [integer]: ConfigVar<string>, [string]: { [integer]: ConfigVar<string>, extra_inputs?: ConfigVar<string>[] } }
---@field linputs? { [integer]: ConfigVar<string>, [string]: { [integer]: ConfigVar<string>, extra_inputs?: ConfigVar<string>[] } }
---Outputs. `extra_outputs` are only supported at the buildtype level.
---@field coutputs? { [integer]: ConfigVar<string>, [string]: { [integer]: ConfigVar<string>, extra_outputs?: ConfigVar<string>[] } }
---@field loutputs? { [integer]: ConfigVar<string>, [string]: { [integer]: ConfigVar<string>, extra_outputs?: ConfigVar<string>[] } }

---@class Config
---@field vars ConfigShape
CONFIG = {
	vars = {
		objdir = "obj/",
		bindir = "bin/",
		suffix = { debug = "d" },
		cflags = {},
		lflags = {},
		cinputs = {},
		linputs = {},
		coutputs = {},
		loutputs = {},
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

---@generic T
---@param func fun(value: T): boolean
---@param ... T[]
function MatchesAny(func, ...)
	local args = { ... }
	for _, arg in ipairs(args) do
		for _, value in ipairs(arg) do
			if func(value) then
				return true
			end
		end
	end
	return false
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

---@param s1 string
---@param s2 string
local function merge_string(s1, s2)
	if s2:sub(0, 1) == " " then
		error("Merged variables should not start with spaces:" .. s2, 4)
	elseif s2:sub(-1) == " " then
		error("Merged variables should not end with spaces: " .. s2, 4)
	end
	return (s1 .. s2)
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
				elseif ((tk_type == "string") and (o_type == "string")) then
					t[k] = merge_string(t[k], o)
				else
					t[k] = o
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

---@param ... ConfigShape
---@return Config
function CONFIG:branch(...)
	local arg = { ... }

	---@class Config
	local ret = table_clone(self)

	for _, other in pairs(arg) do
		---@cast other +Config
		if other.branch then
			error("Configurations should not be combined with each other", 2)
		end
		TableExtend(ret.vars, other)
	end

	-- Discover buildtypes
	ret.buildtypes = {}
	for _, var in pairs(ret.vars) do
		if (type(var) == "table") then
			for buildtype, _ in pairs(var) do
				if (type(buildtype) == "string") then
					ret.buildtypes[buildtype] = {}
				end
			end
		end
	end
	return ret
end

---@param ... string
function CONFIG:render_for_buildtypes(...)
	local fields = { ... }
	local ret = table_clone(self.buildtypes)
	for _, field in pairs(fields) do
		for buildtype, rendered in pairs(ret) do
			rendered[field] = (rendered[field] or {})
			TableExtend(rendered[field], self.vars[field])
			TableExtend(rendered[field], (self.vars[field][buildtype] or {}))
			for buildtype_inner, _ in pairs(ret) do
				rendered[field][buildtype_inner] = nil
			end
		end
	end
	return ret
end

---@param name string
---@param ext string
---@param rule fun(vars: table): table Runs the build rule and returns inputs for further rules.
function CONFIG:CommonC(inputs, name, ext, rule)
	local ret = {}
	local buildtypes = self:render_for_buildtypes(
		"cflags", "cinputs", "coutputs", "suffix"
	)
	for buildtype, vars in pairs(buildtypes) do
		TableExtend(vars.cinputs, inputs)
		vars.coutputs += (self.vars.objdir .. name .. vars.suffix .. ext)
		ret[buildtype] = rule(vars)
	end
	setmetatable(ret, functional_metatable)
	return ret
end

---@param name string
---@param ext string
---@param rule fun(vars: table, basename: string, inps: string): table Runs the build rule and returns inputs for further rules.
function CONFIG:CommonL(inputs, name, ext, rule)
	local ret = {}
	local buildtypes = self:render_for_buildtypes(
		"lflags", "linputs", "loutputs", "suffix"
	)
	for buildtype, vars in pairs(buildtypes) do
		local basename = (name .. vars.suffix)
		TableExtend(vars.linputs, inputs[buildtype])
		vars.loutputs += (self.vars.bindir .. basename .. ext)
		local inps = ""
		for _, input in ipairs(vars.linputs) do
			inps = string.format('%s "%s"', inps, input)
		end
		ret[buildtype] = rule(vars, basename, inps)
	end
	setmetatable(ret, functional_metatable)
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

---Deduplicates and concatenates `flags` with a leading whitespace.
---@param ... string[]
function ConcatFlags(...)
	local seen = {}
	local ret = ""
	ForEach(function (flag)
		if not seen[flag] then
			seen[flag] = true
			ret = (ret .. " " .. flag)
		end
	end, ...)
	return ret
end
