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

local function std_module_fn(module)
	-- Well, SG15 to suggest that compilers use JSON to store module paths, and
	-- both GCC and Clang agreed…
	local modules_json_fn = string.format(
		"\\$(%s -print-file-name=%s.modules.json)", CC, CXX_STDLIB
	)
	return string.format(
		"\\$(dirname %s)/" ..
		[[\$(jq -r '.["modules"][] | select(."logical-name"=="%s")."source-path"' %s)]],
		modules_json_fn,
		module,
		modules_json_fn
	)
end

-- Compiles the C++ standard library modules and returns a shape for using them.
---@param configs Config
---@return ConfigShape
function cxx_std_modules(configs)
	local std = CXXMWithOutput(configs, std_module_fn("std"), "std", true)
	local compat = CXXMWithOutput(
		configs:branch(std), std_module_fn("std.compat"), "std.compat", true
	)
	return TableExtend(std, compat)
end

---Compiles the given C++ module and returns a shape for using it.
---@param configs Config
---@param module_fn string
---@return ConfigShape
function cxxm(configs, module_fn)
	return CXXMWithOutput(configs, module_fn, tup.base(module_fn), false)
end

---@param configs Config
function exe(configs, inputs, name)
	return configs:CommonL(inputs, name, "", function(vars, _, inps)
		-- Inputs must come first to work properly with `-Wl,--as-needed`.
		local cmd = (CXX .. inps .. ' -o "%o"' .. ConcatFlags(vars.lflags))
		return tup.rule(vars.linputs, cmd, vars.loutputs)
	end)
end
