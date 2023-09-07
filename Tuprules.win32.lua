CONFIG.buildtypes.debug.cflags = "/MDd /Od /ZI"
CONFIG.buildtypes.debug.lflags = ""
CONFIG.buildtypes.debug.coutputs = { "%O.idb" }
CONFIG.buildtypes.debug.loutputs = { "%O.ilk" }

CONFIG.buildtypes.release.cflags = "/MT /O2 /GL /Zi"
CONFIG.buildtypes.release.lflags = "/OPT:REF /OPT:ICF /LTCG"
CONFIG.buildtypes.release.coutputs = { }
CONFIG.buildtypes.release.loutputs = { }

function cxx(configs, inputs)
	local ret = {}
	for buildtype, vars in pairs(configs.buildtypes) do
		outputs = { (configs.base.objdir .. "%B" .. vars.suffix .. ".obj") }
		outputs["extra_outputs"] = { "%O.pdb" }
		outputs["extra_outputs"] += vars.coutputs
		objs = tup.foreach_rule(
			inputs, (
				"cl /nologo /c /Qpar /Fo:%o " ..

				-- /Fd is a rather clunky way of overriding vc140.pdb, but we'd
				-- really like to avoid that ghost node, which causes a second
				-- unnecessary link pass if tup is launched immediately after a
				-- successful build.
				"/Fd:%O.pdb " ..

				configs.base.cflags .. " " .. vars.cflags .. " %f"
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

function exe(configs, inputs, exe_basename)
	ret = {}
	for buildtype, vars in pairs(configs.buildtypes) do
		basename = (exe_basename .. vars.suffix)
		outputs = { (configs.base.bindir .. "/" .. basename .. ".exe") }
		outputs["extra_outputs"] = { "%O.pdb" }
		outputs["extra_outputs"] += vars.loutputs
		ret[buildtype] += tup.rule(
			inputs[buildtype], (
				"link /nologo /DEBUG:FULL " ..
				configs.base.lflags .. " " ..
				vars.lflags .. " " ..
				"/PDBALTPATH:" .. basename .. ".pdb /out:%o %f"
			),
			outputs
		)
	end
	return ret
end
