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

		-- We'd like to have something like COFF .lib files to avoid needless
		-- relinking of dependent binaries via Tup's ^o^ flag, just as we do in
		-- the MSVC toolchain. However, Unix linkers typically take the list of
		-- dynamic symbols from the proper .so file, so there's no direct
		-- equivalent that we can simply produce during linking.
		-- Hence, we have to fiddle a bit: Since the link invocation for those
		-- binaries must never see the real `.so` file (because Tup would then
		-- register it as a regular dependency and then still relink on every
		-- code change), we need to replace that `.so` with some kind of dummy.
		-- That file must somehow contain all exported symbols, but *mustn't*
		-- contain any actual code to remain unchanged as long as the set of
		-- exported functions doesn't change.
		--
		-- And as it turns out, there are indeed several ways to create such a
		-- dummy `.so` after the fact. The seemingly most robust and portable
		-- option involves parsing the list of symbols into an ASM file:
		--
		-- 1) Read out the dynamic symbols using `nm`
		-- 2) Transform this list of symbols into an assembly file that defines
		--    each symbol as a function with an explicit 1-byte size, but
		--    without emitting any code
		-- 3) Generate a `.so` from just this assembly file
		--
		-- (Linker scripts with `= 0;` symbol assignments seem to work at
		-- first, but break when compiling with `-fno-plt`, which is part of
		-- the default `CFLAGS` set by Arch Linux's `makepkg`. Also, they
		-- require a slightly ugly empty source file, because the linker
		-- insists on seeing at least one source file.)
		--
		-- `nm` is an integral part of the binutils required for every Unix
		-- compiler toolchain, and `sed` is one of the most widespread tools
		-- ever, so this should work nicely even in minimal MinGW setups.
		-- By adding `^o^` to step 3) *and* 2), we can even skip the additional
		-- link command as long as the interface doesn't change.
		-- As a nice side effect, this dummy file also replaces the typical
		-- suffix-less .so symlink that would typically get passed to the
		-- linker.

		local real_fn = tup.rule(vars.linputs, cmd, vars.loutputs)[1]
		local major_fn = (self.vars.bindir .. soname)
		local dummy_s_fn = (self.vars.objdir .. basename .. ".S")
		local link_fn = (self.vars.bindir .. basename .. ".so")

		local dummy_gen_cmd = (
			'^o^ nm -DUWj "%f" | ' ..
			'sed "s/.*/.global &\\n.type &, @function\\n&:\\n.size &, 1/" >"%o"'
		)
		local dummy_link_cmd = string.format(
			'^o^ %s "%%f" -nostdlib %s', CC, so_flags
		)

		tup.rule(real_fn, dummy_gen_cmd, dummy_s_fn)
		local extra_inputs = tup.rule(dummy_s_fn, dummy_link_cmd, link_fn)[1]
		extra_inputs += tup.rule(
			{}, ('^o^ ln -s "' .. tup.file(real_fn) .. '" "%o"'), major_fn
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
