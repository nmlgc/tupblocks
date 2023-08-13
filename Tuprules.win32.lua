CONFIGS.debug.cflags = "/MDd /Od /ZI"
CONFIGS.debug.lflags = ""
CONFIGS.debug.coutputs = { "%O.idb" }
CONFIGS.debug.loutputs = { "%O.ilk" }

CONFIGS.release.cflags = "/MT /Ox /Gy /GL /Zi"
CONFIGS.release.lflags = " /OPT:REF /OPT:ICF /LTCG"
CONFIGS.release.coutputs = { }
CONFIGS.release.loutputs = { }

function cxx(configs, inputs, extra_flags, objdir)
	ret = {}
	for config_name, vars in pairs(configs) do
		outputs = { (BASE.objdir .. vars.objdir .. objdir .. "/%B.obj") }
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

				BASE.cflags .. " " ..
				vars.cflags .. " " ..
				extra_flags ..
				" %f"
			), outputs
		)
		ret[config_name] += objs
		for _, fn in pairs(objs) do
			ret[config_name]["extra_inputs"] += string.gsub(fn, ".obj$", ".pdb")
		end
	end
	return ret
end

function exe(configs, inputs, extra_flags, exe_basename)
	ret = {}
	for config_name, vars in pairs(configs) do
		basename = (exe_basename .. vars.suffix)
		outputs = { (BASE.bindir .. "/" .. basename .. ".exe") }
		outputs["extra_outputs"] = { "%O.pdb" }
		outputs["extra_outputs"] += vars.loutputs
		ret[config_name] += tup.rule(
			inputs[config_name], (
				"link /nologo /DEBUG:FULL " ..
				BASE.lflags .. " " ..
				vars.lflags .. " " ..
				extra_flags .. " " ..
				"/PDBALTPATH:" .. basename .. ".pdb /out:%o %f"
			),
			outputs
		)
	end
	return ret
end
