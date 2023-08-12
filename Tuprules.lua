CONFIGS = {}

if (tup.getconfig("DEBUG") != "n") then
	CONFIGS.debug = {
		objdir = "Debug/",
		suffix = "d",
	}
end
if (tup.getconfig("RELEASE") != "n") then
	CONFIGS.release = {
		objdir = "Release/",
		suffix = "",
	}
end

tup.include(string.format("Tuprules.%s.lua", tup.getconfig("TUP_PLATFORM")))
