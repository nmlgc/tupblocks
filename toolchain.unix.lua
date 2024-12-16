--- Common rule definitions for compilers with Unix-like frontends

CONFIG = CONFIG:branch({
	cflags = {
		"-g",
		debug = { "-O0" },
		release = { "-O3", "-DNDEBUG" },
	},
})

---@param compiler string
---@param configs Config
---@param out_basename string
---@param ext string
function UnixC(compiler, configs, inputs, out_basename, ext)
	return configs:CommonC(inputs, out_basename, ext, function(vars)
		local cmd = (compiler .. ' -c -o "%o"' .. ConcatFlags(vars.cflags))

		-- If we have no array part, we assume the inputs to be part of
		-- `vars.cflags`. Required for substituted input file names.
		if (#vars.cinputs == 0) then
			return tup.rule(vars.cinputs, cmd, vars.coutputs)
		end
		return tup.foreach_rule(vars.cinputs, (cmd .. ' "%f"'), vars.coutputs)
	end)
end

---@param configs Config
function cc(configs, inputs)
	return UnixC(CC, configs, inputs, "%B", ".o")
end

---@param configs Config
function cxx(configs, inputs)
	return UnixC(CXX, configs, inputs, "%B", ".o")
end

---@param configs Config
function exe(configs, inputs, name)
	return configs:CommonL(inputs, name, "", function(vars, _, inps)
		local cmd = (CXX .. ConcatFlags(vars.lflags) .. ' -o "%o"' .. inps)
		return tup.rule(vars.linputs, cmd, vars.loutputs)
	end)
end
