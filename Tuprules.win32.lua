---@class ConfigShape
---@field cflags? ConfigVarBuildtyped<string>
---@field lflags? ConfigVarBuildtyped<string>
---@field cinputs? ConfigVarBuildtyped<string>
---@field linputs? ConfigVarBuildtyped<string>
---@field coutputs? ConfigVarBuildtyped<string>
---@field loutputs? ConfigVarBuildtyped<string>

CONFIG = CONFIG:branch({
	cflags = {
		debug = { "/MDd", "/Od", "/ZI" },
		release = { "/MT", "/O2", "/GL", "/Zi", "/DNDEBUG" },
	},
	lflags = {
		release = { "/OPT:REF", "/OPT:ICF", "/LTCG" },
	},
	cinputs = {},
	linputs = {},
	coutputs = { debug = { "%O.idb" } },
	loutputs = { debug = { "%O.ilk" } },
})

---@param configs Config
function cxx(configs, inputs)
	local ret = {}
	local buildtypes = configs:render_for_buildtypes(
		"cflags", "cinputs", "coutputs", "suffix"
	)
	for buildtype, vars in pairs(buildtypes) do
		vars.cinputs += inputs
		vars.coutputs += (configs.vars.objdir .. "%B" .. vars.suffix .. ".obj")
		vars.coutputs.extra_outputs += { "%O.pdb" }
		objs = tup.foreach_rule(
			vars.cinputs, (
				"cl /nologo /c /Qpar /Fo:%o " ..

				-- /Fd is a rather clunky way of overriding vc140.pdb, but we'd
				-- really like to avoid that ghost node, which causes a second
				-- unnecessary link pass if tup is launched immediately after a
				-- successful build.
				"/Fd:%O.pdb" ..

				ConcatFlags(vars.cflags) .. " \"%f\""
			), vars.coutputs
		)
		ret[buildtype] += objs
		for _, fn in pairs(objs) do
			ret[buildtype]["extra_inputs"] += string.gsub(fn, ".obj$", ".pdb")
		end
	end
	setmetatable(ret, functional_metatable)
	return ret
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
		cflags = { "/ifcOutput %O.ifc" },
		coutputs = { "%O.ifc" },
	}
	module_compile.cflags += module_cflags

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
				"/reference %s=%s", module, ifc:gsub("/", "\\")
			)
			ret.cinputs[buildtype] += ifc
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
	local ret = {}
	local buildtypes = configs:render_for_buildtypes(
		"lflags", "linputs", "loutputs", "suffix"
	)
	for buildtype, vars in pairs(buildtypes) do
		local basename = (name .. vars.suffix)
		local lib = (configs.vars.objdir .. basename .. ".lib")
		local dll = (configs.vars.bindir .. basename .. ".dll")
		vars.loutputs += dll
		vars.loutputs.extra_outputs += { "%O.pdb", lib }
		tup.rule(
			TableExtend(vars.linputs, inputs[buildtype]), (
				"link /nologo /DEBUG:FULL /DLL /NOEXP /IMPLIB:" .. lib ..
				ConcatFlags(vars.lflags) .. " " ..
				"/MANIFEST:EMBED /PDBALTPATH:" .. basename .. ".pdb /out:%o %f"
			),
			vars.loutputs
		)
		ret[buildtype] += lib
	end
	setmetatable(ret, functional_metatable)
	return ret
end

---@param configs Config
function exe(configs, inputs, exe_basename)
	ret = {}
	local buildtypes = configs:render_for_buildtypes(
		"lflags", "linputs", "loutputs", "suffix"
	)
	for buildtype, vars in pairs(buildtypes) do
		basename = (exe_basename .. vars.suffix)
		vars.loutputs += (configs.vars.bindir .. "/" .. basename .. ".exe")
		vars.loutputs.extra_outputs += { "%O.pdb" }
		ret[buildtype] += tup.rule(
			TableExtend(vars.linputs, inputs[buildtype]), (
				"link /nologo /DEBUG:FULL" ..
				ConcatFlags(vars.lflags) .. " " ..
				"/MANIFEST:EMBED /PDBALTPATH:" .. basename .. ".pdb /out:%o %f"
			),
			vars.loutputs
		)
	end
	return ret
end
