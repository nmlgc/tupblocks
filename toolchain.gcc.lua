--- Rule definitions for GCC

tup.include("toolchain.unix.lua")
tup.import("CC=gcc")
tup.import("CXX_STDLIB=libstdc++")
tup.import("CXX=g++")

CONFIG = CONFIG:branch({
	-- cflags = { release = { "-flto" } },
	-- lflags = { release = { "-flto" } },
})

---@param configs Config
---@param module_fn {} | string
---@param module string
---@param substituted boolean
---@return ConfigShape
function CXXMWithOutput(configs, module_fn, module, substituted)
	---@type ConfigShape
	local consume = {
		cflags = { "-std=c++2c", "-fmodules-ts" },
		cinputs = {},
		linputs = {},
	}

	---@type ConfigShape
	local compile = { coutputs = {} }

	local buildtypes = configs:render_for_buildtypes("cflags", "suffix")
	for buildtype, vars in pairs(buildtypes) do
		local module_basename = (configs.vars.objdir .. module .. vars.suffix)
		local gcm_fn = (module_basename .. ".gcm")
		local map_fn = (module_basename .. ".modulemap")
		local cmd = string.format('echo %s "%s"', module, gcm_fn)
		local echo_inputs = {}

		-- Amend a previously existing module map…
		for i, flag in ipairs(vars.cflags) do
			if flag:match('-fmodule%-mapper=') then
				local mapper_prev = flag:match('-fmodule%-mapper="(.+)"')
				echo_inputs += mapper_prev
				cmd = ('cat "' .. mapper_prev .. '" && ' .. cmd)
			end
		end
		tup.rule(echo_inputs, string.format("(%s)>%%o", cmd), map_fn)

		consume.cinputs[buildtype] = { extra_inputs = map_fn }
		consume.cflags[buildtype] = { '-fmodule-mapper="' .. map_fn .. '"' }
		compile.coutputs[buildtype] = { extra_outputs = { gcm_fn } }
	end

	local gcm_cfg = configs:branch(consume, compile)
	local input = module_fn
	if substituted then
		input = {}
		gcm_cfg = gcm_cfg:branch({ cflags = module_fn })
	end

	consume.linputs = UnixC(CXX, gcm_cfg, input, module, ".o")
	for buildtype, _ in pairs(configs.buildtypes) do
		consume.cinputs[buildtype] = {
			extra_inputs = compile.coutputs[buildtype].extra_outputs
		}
	end
	return consume
end
