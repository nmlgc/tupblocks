--- Rule definitions for Clang

tup.include("toolchain.unix.lua")
tup.import("CC=clang")
tup.import("CXX_STDLIB=libc++")
tup.import("CXX=clang++ -stdlib=" .. CXX_STDLIB)

CONFIG = CONFIG:branch({
	cflags = { release = { "-flto=full" } },
	lflags = { release = { "-flto=full" } },
})

---@param module_fn {} | string
---@param module string
---@param substituted boolean
---@return ConfigShape
function CONFIG:CXXMWithOutput(module_fn, module, substituted)
	local cpp2c = "-std=c++2c"
	local compile = self:branch({
		cflags = { "-Wno-reserved-module-identifier", cpp2c }
	})

	local pcm_cfg = compile:branch({
		cflags = {
			"--precompile",
			"-x c++-module", -- supports extensions other than `.cppm`
		}
	})
	local input = module_fn
	if substituted then
		input = {}
		pcm_cfg = pcm_cfg:branch({ cflags = module_fn })
	end
	local module_pcm = pcm_cfg:UnixC(CXX, input, module, ".pcm")

	local o_cfg = compile:branch({ cinputs = module_pcm })

	---@type ConfigShape
	local ret = {
		cflags = { cpp2c },
		cinputs = {},
		linputs = o_cfg:UnixC(CC, {}, module, ".o"),
	}
	for buildtype, pcm in pairs(module_pcm) do
		ret.cflags[buildtype] += string.format(
			'-fmodule-file=%s="%s"', module, pcm[1]
		)
		ret.cinputs[buildtype] = { extra_inputs = pcm }
	end
	return ret
end
