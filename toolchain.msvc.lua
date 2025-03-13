--- Rule definitions for Microsoft Visual Studio

CONFIG = CONFIG:branch({
	cflags = {
		debug = { "/MDd", "/Od" },
		release = { "/MT", "/O2", "/GL", "/DNDEBUG" },
	},
	lflags = {
		"/MANIFEST:EMBED",
		release = { "/OPT:REF", "/OPT:ICF", "/LTCG" },
	},
	loutputs = { debug = { extra_outputs = { "%O.ilk" } } },
})

function CONFIG:cxx(inputs)
	return self:CommonC(inputs, "%B", ".obj", function(vars)
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

CONFIG.cc = CONFIG.cxx

---Compiles the given C++ module and returns a shape for using it.
---@param module_fn string
---@return ConfigShape
function CONFIG:cxxm(module_fn)
	local module = tup.base(module_fn)
	local module_cflags = { "/EHsc", "/std:c++latest" }

	---@type ConfigShape
	local module_compile = {
		cflags = { '/ifcOutput "%O.ifc"' },
		coutputs = {},
	}
	module_compile.cflags += module_cflags

	-- Transparent support for /analyze…
	---@param flag string
	local function has_analyze(flag)
		-- Thankfully, cl.exe checks for this flag in a case-sensitive way.
		return (flag:match("/analyze") ~= nil)
	end

	local buildtypes = self:render_for_buildtypes("cflags")
	for buildtype, vars in pairs(buildtypes) do
		-- `extra_outputs` are only supported at the buildtype level.
		module_compile.coutputs[buildtype] = { extra_outputs = { "%O.ifc" } }
		if MatchesAny(has_analyze, vars.cflags) then
			module_compile.coutputs[buildtype].extra_outputs += { "%O.ifcast" }
		end
	end

	---@type ConfigShape
	local ret = {
		cflags = module_cflags,
		cinputs = {},
		linputs = self:branch(module_compile):cxx(module_fn),
	}
	for buildtype, objs in pairs(ret.linputs) do
		local obj = objs[1]
		local ifc = obj:gsub(".obj$", ".ifc")
		ret.cflags[buildtype] += string.format(
			'/reference %s="%s"', module, ifc:gsub("/", "\\")
		)
		ret.cinputs[buildtype] = { extra_inputs = { ifc } }
		if (#module_compile.coutputs[buildtype].extra_outputs == 2) then
			ret.cinputs[buildtype].extra_inputs += obj:gsub(".obj$", ".ifcast")
		end
	end
	return ret
end

-- Compiles the C++ standard library modules and returns a shape for using them.
---@return ConfigShape
function CONFIG:cxx_std_modules()
	tup.import("VCToolsInstallDir")

	-- tup turns `VCToolsInstallDir` into a table if it contains a space, but
	-- concatenating a string turns it back into a string?!
	local dir = (VCToolsInstallDir .. "\\modules"):gsub("\\", "/")
	local std = self:cxxm(dir .. "/std.ixx")
	local compat = self:branch(std):cxxm(dir .. "/std.compat.ixx")
	return TableExtend(std, compat)
end

function CONFIG:rc(inputs)
	local ret = {}
	outputs = { (self.vars.objdir .. "%B.res") }
	objs = tup.foreach_rule(inputs, "rc /nologo /n /fo %o %f", outputs)
	for buildtype, vars in pairs(self.buildtypes) do
		ret[buildtype] += objs
	end
	setmetatable(ret, functional_metatable)
	return ret
end

function CONFIG:dll(inputs, name)
	return self:CommonL(inputs, name, ".dll", function(vars, basename, inps)
		local lib = (self.vars.objdir .. basename .. ".lib")
		vars.loutputs.extra_outputs += { "%O.pdb", lib }
		local cmd = (
			'link /nologo /DEBUG:FULL /DLL /NOEXP /IMPLIB:"' .. lib .. '"' ..
			ConcatFlags(vars.lflags) .. " " ..
			'/PDBALTPATH:"' .. basename .. '".pdb /out:"%o"' .. inps
		)
		tup.rule(vars.linputs, cmd, vars.loutputs)
		return lib
	end)
end

function CONFIG:exe(inputs, name)
	return self:CommonL(inputs, name, ".exe", function(vars, basename, inps)
		vars.loutputs.extra_outputs += { "%O.pdb" }
		local cmd = (
			"link /nologo /DEBUG:FULL" ..
			ConcatFlags(vars.lflags) .. " " ..
			'/PDBALTPATH:"' .. basename .. '.pdb" /out:"%o"' .. inps
		)
		return tup.rule(vars.linputs, cmd, vars.loutputs)
	end)
end

---@param name string
function CONFIG:lib(inputs, name)
	local ret = {}
	local buildtypes = self:render_for_buildtypes("suffix")
	for buildtype, vars in pairs(buildtypes) do
		local lib_fn = (self.vars.objdir .. name .. vars.suffix .. ".lib")
		local cmd = 'lib /nologo /out:"%o"'
		for _, input in ipairs(inputs[buildtype]) do
			cmd = string.format('%s "%s"', cmd, input)
		end

		-- Any extra_inputs must be passed through to the linker called after
		-- us, and tup.rule() resets the incoming table value to `nil`.
		local extra_inputs = inputs[buildtype].extra_inputs

		ret[buildtype] += tup.rule(inputs[buildtype], cmd, lib_fn)
		ret[buildtype].extra_inputs = extra_inputs
	end
	setmetatable(ret, functional_metatable)
	return ret
end
