CONFIGS = {
	debug = {
		objdir = "Debug/",
		suffix = "d",
	},
	release = {
		objdir = "Release/",
		suffix = "",
	}
}

SELECTED = {}
if (tup.getconfig("DEBUG") != "n") then
	SELECTED.debug = CONFIGS.debug
end
if (tup.getconfig("RELEASE") != "n") then
	SELECTED.release = CONFIGS.release
end

tup.include(string.format("Tuprules.%s.lua", tup.getconfig("TUP_PLATFORM")))
