---@class ConfigShape
---@field cflags? ConfigVarBuildtyped<string>
---@field lflags? ConfigVarBuildtyped<string>
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
	coutputs = { debug = { "%O.idb" } },
	loutputs = { debug = { "%O.ilk" } },
})

---@param configs Config
function cxx(configs, inputs)
	local ret = {}
	local buildtypes = configs:render_for_buildtypes(
		"cflags", "coutputs", "suffix"
	)
	for buildtype, vars in pairs(buildtypes) do
		outputs = { (configs.vars.objdir .. "%B" .. vars.suffix .. ".obj") }
		outputs["extra_outputs"] = { "%O.pdb" }
		outputs["extra_outputs"] += vars.coutputs
		objs = tup.foreach_rule(
			inputs, (
				"cl /nologo /c /Qpar /Fo:%o " ..

				-- /Fd is a rather clunky way of overriding vc140.pdb, but we'd
				-- really like to avoid that ghost node, which causes a second
				-- unnecessary link pass if tup is launched immediately after a
				-- successful build.
				"/Fd:%O.pdb" ..

				ConcatFlags(vars.cflags) .. " \"%f\""
			), outputs
		)
		ret[buildtype] += objs
		for _, fn in pairs(objs) do
			ret[buildtype]["extra_inputs"] += string.gsub(fn, ".obj$", ".pdb")
		end
	end
	setmetatable(ret, functional_metatable)
	return ret
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
		"lflags", "loutputs", "suffix"
	)
	for buildtype, vars in pairs(buildtypes) do
		local basename = (name .. vars.suffix)
		local lib = (configs.vars.objdir .. basename .. ".lib")
		local dll = (configs.vars.bindir .. basename .. ".dll")
		local outputs = { dll }
		outputs["extra_outputs"] = { "%O.pdb", lib }
		outputs["extra_outputs"] += vars.loutputs
		tup.rule(
			inputs[buildtype], (
				"link /nologo /DEBUG:FULL /DLL /NOEXP /IMPLIB:" .. lib ..
				ConcatFlags(vars.lflags) .. " " ..
				"/MANIFEST:EMBED /PDBALTPATH:" .. basename .. ".pdb /out:%o %f"
			),
			outputs
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
		"lflags", "loutputs", "suffix"
	)
	for buildtype, vars in pairs(buildtypes) do
		basename = (exe_basename .. vars.suffix)
		outputs = { (configs.vars.bindir .. "/" .. basename .. ".exe") }
		outputs["extra_outputs"] = { "%O.pdb" }
		outputs["extra_outputs"] += vars.loutputs
		ret[buildtype] += tup.rule(
			inputs[buildtype], (
				"link /nologo /DEBUG:FULL" ..
				ConcatFlags(vars.lflags) .. " " ..
				"/MANIFEST:EMBED /PDBALTPATH:" .. basename .. ".pdb /out:%o %f"
			),
			outputs
		)
	end
	return ret
end
