--- Rule definitions for Microsoft Visual Studio

---@class ConfigShape
---@field cflags? ConfigVarBuildtyped<string>
---@field lflags? ConfigVarBuildtyped<string>
---@field cinputs? ConfigVarBuildtyped<string>
---@field linputs? ConfigVarBuildtyped<string>
---@field coutputs? ConfigVarBuildtyped<string>
---@field loutputs? ConfigVarBuildtyped<string>

CONFIG = CONFIG:branch({
	cflags = {
		debug = { "/MDd", "/Od" },
		release = { "/MT", "/O2", "/GL", "/DNDEBUG" },
	},
	lflags = {
		release = { "/OPT:REF", "/OPT:ICF", "/LTCG" },
	},
	cinputs = {},
	linputs = {},
	coutputs = {},
	loutputs = { debug = { "%O.ilk" } },
})

---@param configs Config
function cxx(configs, inputs)
	return configs:CommonC(inputs, "%B", ".obj", function(vars)
		local flags = ConcatFlags(vars.cflags)
		vars.coutputs.extra_outputs += { "%O.pdb" }
		-- /Fd is a rather clunky way of overriding vc140.pdb, but we'd really
		-- like to avoid that ghost node, which causes a second unnecessary
		-- link pass if tup is launched immediately after a successful build.
		local cmd = (
			'cl /nologo /c /Qpar /Zi /Fo:"%o" /Fd:"%O.pdb"' .. flags .. ' "%f"'
		)
		local ret = tup.foreach_rule(vars.cinputs, cmd, vars.coutputs)
		for _, fn in ipairs(ret) do
			ret.extra_inputs += string.gsub(fn, ".obj$", ".pdb")
		end
		return ret
	end)
end

---Compiles the given C++ modules and returns a shape for using them.
---@param configs Config
---@return ConfigShape
function cxxm(configs, inputs)
	if (type(inputs) ~= "table") then
		inputs = { inputs }
	end
	local module_cflags = { "/EHsc", "/std:c++latest" }

	---@type ConfigShape
	local module_compile = {
		cflags = { '/ifcOutput "%O.ifc"' },
		coutputs = { "%O.ifc" },
	}
	module_compile.cflags += module_cflags

	-- Transparent support for /analyze…
	---@param flag string
	local function has_analyze(flag)
		-- Thankfully, cl.exe checks for this flag in a case-sensitive way.
		return (flag:match("/analyze") ~= nil)
	end

	local buildtypes = configs:render_for_buildtypes("cflags")
	for buildtype, vars in pairs(buildtypes) do
		if MatchesAny(has_analyze, vars.cflags) then
			module_compile.coutputs[buildtype] = { "%O.ifcast" }
		end
	end

	local module_obj = cxx(configs:branch(module_compile), inputs)

	---@type ConfigShape
	local ret = {
		cflags = module_cflags,
		cinputs = {},
		lflags = {},
		linputs = {},
	}
	for buildtype, objs in pairs(module_obj) do
		for i, obj in ipairs(objs) do
			local module = tup.base(inputs[i])
			local ifc = obj:gsub(".obj$", ".ifc")
			ret.cflags[buildtype] += string.format(
				'/reference %s="%s"', module, ifc:gsub("/", "\\")
			)
			ret.cinputs[buildtype] += ifc
			if (module_compile.coutputs[buildtype] ~= nil) then
				ret.cinputs[buildtype] += obj:gsub(".obj$", ".ifcast")
			end
			ret.lflags[buildtype] += obj
		end
		ret.linputs[buildtype] += objs
		ret.linputs[buildtype] += objs.extra_inputs
	end
	return ret
end

-- Compiles the C++ standard library modules and returns a shape for using them.
---@param configs Config
---@return ConfigShape
function cxx_std_modules(configs)
	tup.import("VCToolsInstallDir")

	-- tup turns `VCToolsInstallDir` into a table if it contains a space, but
	-- concatenating a string turns it back into a string?!
	local dir = (VCToolsInstallDir .. "\\modules"):gsub("\\", "/")
	local std = cxxm(configs, (dir .. "/std.ixx"))
	local compat = cxxm(configs:branch(std), (dir .. "/std.compat.ixx"))
	return TableExtend(std, compat)
end

---@param configs Config
function rc(configs, inputs)
	local ret = {}
	outputs = { (configs.vars.objdir .. "%B.res") }
	objs = tup.foreach_rule(inputs, "rc /nologo /n /fo %o %f", outputs)
	for buildtype, vars in pairs(configs.buildtypes) do
		ret[buildtype] += objs
	end
	setmetatable(ret, functional_metatable)
	return ret
end

---@param configs Config
function dll(configs, inputs, name)
	return configs:CommonL(inputs, name, ".dll", function(vars, basename, inps)
		local lib = (configs.vars.objdir .. basename .. ".lib")
		vars.loutputs.extra_outputs += { "%O.pdb", lib }
		local cmd = (
			"link /nologo /DEBUG:FULL /DLL /NOEXP /IMPLIB:" .. lib ..
			ConcatFlags(vars.lflags) .. " /MANIFEST:EMBED " ..
			'/PDBALTPATH:"' .. basename .. '".pdb /out:"%o"' .. inps
		)
		tup.rule(vars.linputs, cmd, vars.loutputs)
		return lib
	end)
end

---@param configs Config
function exe(configs, inputs, name)
	return configs:CommonL(inputs, name, ".exe", function(vars, basename, inps)
		vars.loutputs.extra_outputs += { "%O.pdb" }
		local cmd = (
			"link /nologo /DEBUG:FULL" ..
			ConcatFlags(vars.lflags) .. " /MANIFEST:EMBED " ..
			'/PDBALTPATH:"' .. basename .. '.pdb" /out:"%o"' .. inps
		)
		return tup.rule(vars.linputs, cmd, vars.loutputs)
	end)
end
