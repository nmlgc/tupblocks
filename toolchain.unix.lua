--- Common rule definitions for compilers with Unix-like frontends

-- Controls the path `-print-file-name` returns for the module JSON file.
tup.export("COMPILER_PATH")

CONFIG = CONFIG:branch({
	cflags = {
		"-g",
		debug = { "-O0" },
		release = { "-O3", "-DNDEBUG" },
	},
})

---@param compiler string
---@param out_basename string
---@param ext string
function CONFIG:UnixC(compiler, inputs, out_basename, ext)
	return self:CommonC(inputs, out_basename, ext, function(vars)
		local cmd = (compiler .. ' -c -o "%o"' .. ConcatFlags(vars.cflags))

		-- If we have no array part, we assume the inputs to be part of
		-- `vars.cflags`. Required for substituted input file names.
		if (#vars.cinputs == 0) then
			return tup.rule(vars.cinputs, cmd, vars.coutputs)
		end
		return tup.foreach_rule(vars.cinputs, (cmd .. ' "%f"'), vars.coutputs)
	end)
end

function CONFIG:cc(inputs)
	return self:UnixC(CC, inputs, "%B", ".o")
end

function CONFIG:cxx(inputs)
	return self:UnixC(CXX, inputs, "%B", ".o")
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
---@return ConfigShape
function CONFIG:cxx_std_modules()
	local std = self:CXXMWithOutput(std_module_fn("std"), "std", true)
	local compat = self:branch(std):CXXMWithOutput(
		std_module_fn("std.compat"), "std.compat", true
	)
	return TableExtend(std, compat)
end

---Compiles the given C++ module and returns a shape for using it.
---@param module_fn string
---@return ConfigShape
function CONFIG:cxxm(module_fn)
	return self:CXXMWithOutput(module_fn, tup.base(module_fn), false)
end

function CONFIG:exe(inputs, name)
	return self:CommonL(inputs, name, "", function(vars, _, inps)
		-- Inputs must come first to work properly with `-Wl,--as-needed`.
		local cmd = (CXX .. inps .. ' -o "%o"' .. ConcatFlags(vars.lflags))
		return tup.rule(vars.linputs, cmd, vars.loutputs)
	end)
end

function CONFIG:lib(inputs, _)
	return inputs
end
