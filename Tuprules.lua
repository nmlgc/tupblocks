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

local function info(str)
	print(string.char(27) .. '[0;34m' .. str .. string.char(27) .. '[0m')
end

tup.import("CFLAGS")
tup.import("LFLAGS")
if (CFLAGS ~= nil) then
	info("ℹ️ Using initial CFLAGS from environment: `" .. CFLAGS .. "`")
end
if (LFLAGS ~= nil) then
	info("ℹ️ Using initial LFLAGS from environment: `" .. LFLAGS .. "`")
end

---@class Config
---@field vars ConfigShape
CONFIG = {
	vars = {
		objdir = "obj/",
		bindir = "bin/",
		suffix = { debug = "d" },
		cflags = CFLAGS,
		lflags = LFLAGS,
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
function First(func, ...)
	local args = { ... }
	for _, arg in ipairs(args) do
		for _, value in ipairs(arg) do
			if func(value) then
				return value
			end
		end
	end
	return nil
end

---@generic T
---@param func fun(value: T): boolean
---@param ... T[]
function MatchesAny(func, ...)
	return (First(func, ...) ~= nil)
end

---@param flag string
---@return ConfigVarFunction<string[]>
function flag_remove(flag)
	return function(prev)
		for i, prev_flag in ipairs(prev) do
			if string.match(prev_flag, flag) then
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

---Turn cflags and lflags from environment variables into a
---[ConfigShape](lua://ConfigShape). Useful for importing flags from pkg-config
---without embedding the query command line into every build rule. You can pass
---multiple prefixes to be included in the single returned shape, but this
---function returns `nil` if even just one of the environment variables is
---missing.
---@param ... string Environment variable prefixes
function EnvConfig(...)
	---@type ConfigShape
	local ret = { cflags = {}, lflags = {} }
	for _, prefix in pairs({ ... }) do
		local var_c = (prefix .. "_cflags")
		local var_l = (prefix .. "_lflags")
		tup.import(var_c)
		tup.import(var_l)
		if ((_G[var_c] == nil) or (_G[var_l] == nil)) then
			return nil
		end
		ret.cflags += _G[var_c]
		ret.lflags += _G[var_l]
	end
	return ret
end

---Creates a C header file with macros `#define`d according to the given table.
---`false` values are turned into `#undef`. Returns `fn`.
---@param fn string Output file name
---@param tbl { [string]: string | false } Macros and their values
function Header(fn, tbl)
	local quote = ""
	if (tup.getconfig("TUP_PLATFORM") ~= "win32") then
		quote = "'"
	end

	-- Sort the incoming keys, so that we output them in a deterministic order
	---@type string[]
	local macros = {}
	for macro in pairs(tbl) do
		table.insert(macros, macro)
	end
	table.sort(macros)

	local cmd = ""
	for _, macro in pairs(macros) do
		if (#cmd == 0) then
			cmd = ("(echo " .. quote)
		else
			cmd = (cmd .. quote .. "&& echo " .. quote)
		end

		local val = tbl[macro]
		if (val == false) then
			cmd = string.format('%s#undef %s', cmd, macro)
		else
			val = val:gsub("\\", "\\\\")
			cmd = string.format('%s#define %s "%s"', cmd, macro, val)
		end
	end
	cmd = (cmd .. quote .. ")")
	tup.rule({}, (cmd .. '>"%o"'), fn)
	return fn
end

---Creates a C header file with macros `#define`d according to the given
---environment variables. Returns `fn`.
---@param fn string Output file name
---@param vars string[] Environment variables
function EnvHeader(fn, vars)
	local tbl = {}
	for _, var in pairs(vars) do
		tup.import(var)
		if (_G[var] == nil) then
			tbl[var] = false
		else
			tbl[var] = (_G[var] .. "")
		end
	end
	return Header(fn, tbl)
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
