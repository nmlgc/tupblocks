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
		local cmd = (
			'^j^ ' .. compiler .. ' -c -o "%o"' .. ConcatFlags(vars.cflags)
		)

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

---@param version_major string Mandatory major version
---@param version_minor string? Optional minor version
function CONFIG:dll(inputs, name, version_major, version_minor)
	local libname = ("lib" .. name)
	local soname_suffix = (".so." .. version_major)
	local ext = soname_suffix
	if version_minor and (version_minor:len() > 0) then
		ext = (ext .. "." .. version_minor)
	end
	return self:CommonL(inputs, libname, ext, function(vars, basename, inps)
		local soname = (basename .. soname_suffix)
		local so_flags = ConcatFlags({
			'-fPIC', '-shared', ('-Wl,-soname,' .. soname), '-o "%o"',
		})
		local cmd = (CXX .. inps .. so_flags .. ' ' .. ConcatFlags(vars.lflags))

		local LN_CMD = '^o^ ln -s "%s" "%%o"'
		local real_fn = tup.rule(vars.linputs, cmd, vars.loutputs)[1]
		local major_fn = (self.vars.bindir .. soname)
		local link_fn = (self.vars.bindir .. basename .. ".so")
		local extra_inputs = real_fn
		extra_inputs += tup.rule(
			{}, string.format(LN_CMD, tup.file(real_fn)), major_fn
		)
		extra_inputs += tup.rule(
			{}, string.format(LN_CMD, tup.file(major_fn)), link_fn
		)
		return {
			lflags = {
				("-L" .. self.vars.bindir),
				("-l" .. basename:sub(4)),
				"-Wl,-rpath,'$ORIGIN'"
			},
			linputs = { extra_inputs = extra_inputs },
		}
	end)
end

function CONFIG:exe(inputs, name)
	return self:CommonL(inputs, name, "", function(vars, _, inps)
		-- Inputs must come first to work properly with `-Wl,--as-needed`.
		local cmd = (CXX .. inps .. ' -o "%o"' .. ConcatFlags(vars.lflags))
		return { linputs = tup.rule(vars.linputs, cmd, vars.loutputs) }
	end)
end

function CONFIG:lib(inputs, _)
	return inputs
end
