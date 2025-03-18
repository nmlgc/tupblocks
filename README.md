# Opinionated building blocks for the Tup build system

[![Code Nutrition: O+ S++ I C E- !PS](http://code.grevit.net:8084/badge/O%2B_S%2B%2B_I_C_E-___!PS)](http://code.grevit.net:8084/facts/O%2B_S%2B%2B_I_C_E-___!PS)

The missing layer between [Tup](https://gittup.org/tup) and your C/C++ compiler binaries, providing opinionated flags for typical debug/release mode settings.
My fourth attempt at writing such a layer, and finally almost not janky.
Provides first-class support for [C++23 Standard Library Modules (P2465R3)](https://wg21.link/P2465R3).

Currently supports:

* **Visual Studio** on Windows

* **GCC** and **Clang** on Linux.
  C++23 Standard Library Modules unfortunately require `jq` as a build-time dependency because [SG15 thought that forcing a JSON parser upon build systems was a good idea](https://www.open-std.org/jtc1/sc22/wg21/docs/papers/2024/p3286r0.pdf).

## The idea

* Build **configurations** form a branching tree.

  Every branch can concatenate new command-line flags or subdirectories at the end of the configuration it branches off of.

* Build **types** are our concept of variants, and are always part of the regular build graph.

  [Tup's variant feature](https://gittup.org/tup/manual.html#lbAL) replaces the regular in-tree build paradigm with an out-of-tree build, and even duplicates the entire directory structure of the tree inside the variant directory.
  I don't like this, so let's just duplicate build rules and distinguish buildtypes with tried-and-true suffixes. If you only need to build a subset of a project's buildtypes, use [Tup's partial update feature](https://gittup.org/tup/manual.html#lbAD) to skip the others while leaving any of their previous outputs in the tree.

## Usage

This example assumes the following directory structure:

* 📂 `src_of_project`
  * 🗒️ `*.cpp`
  * 🗒️ `windows_resource.rc`
* 📂 `vendor`
  * 📂 `a_thirdparty_library`
    * 📂 `include`
      * 🗒️ `*.h`
    * 📂 `src`
      * 🗒️ `*.c`
      * 🗒️ `linux_exclusive.c`
  * 📁 **`tupblocks`** (Checkout of this repo, e.g. as a Git submodule or [subrepo](https://github.com/ingydotnet/git-subrepo))
* `Tupfile.ini`
* `Tupfile.lua`

The `Tupfile.lua` for this example then would look something like this:

```lua
-- This repo is designed to be either included as a submodule, or downloaded
-- into your build tree in another way.
tup.include("vendor/tupblocks/Tuprules.lua")

-- Include the rule functions for the desired build platform, together with
-- default flags for debug and release builds.
if tup.getconfig("TUP_PLATFORM") == "win32" then
	tup.include("vendor/tupblocks/toolchain.msvc.lua")
end

-- Build the third-party library
-- -----------------------------

-- sourcepath() provides convenient helper functions for globbing, filtering,
-- and subdirectory joining.
THE_LIB = sourcepath("vendor/a_thirdparty_library/")

-- Define the flags exclusive to this library, as separate tables. All of these
-- configuration and flag tables follow the `ConfigShape` class declared in
-- `Tuprules.lua`.
--
-- The `ConfigVarBuildtyped` fields consist of
-- • an array of generic arguments in the integer part of their table, and
-- • buildtype-specific values in the associative part, using the name of the
--   buildtype as the key of another array.
-- The existing buildtypes are determined by looking at these tables and don't
-- need to be separately declared. The toolchain-specific scripts typically
-- inject default arguments for `debug` and `release` buildtypes into the root
-- configuration.
THE_LIB_COMPILE = {
	cflags = {
		-- Required by the library for DLL builds. Used for every buildtype.
		"/DDLL_EXPORT",

		-- Multiple flags should be passed as a table. Every logical flag
		-- should be its own element, and can consist of multiple
		-- space-separated words. This allows redundant flags to be
		-- deduplicated when building the final command lines.
		-- Since both MSVC and GCC-like compilers support the dash syntax, it
		-- makes sense to use it for cross-platform settings.
		debug = { "-DDEBUG", "-DDEBUG_VERBOSE" },

		-- The base CONFIG table uses the /GL flag for Visual Studio release
		-- builds by default, but this library doesn't like it. Merged settings
		-- can also be functions that are applied to the current value, which
		-- we can use to remove the flag using the flag_remove() helper.
		-- Based on a true story:
		--
		-- https://github.com/libsdl-org/SDL/commit/ae7446a9591299eef719f82403c
		release = { cflags = flag_remove("/GL") }
	},
	objdir = "the_lib/", -- creates a new namespace for object files
}

-- Flags for linking to the library.
THE_LIB_LINK = { cflags = ("-I" .. THE_LIB.join("include/")) }

-- Create the actual configuration by branching off from the root and adding
-- the compile and link flags.
the_lib_cfg = CONFIG:branch(THE_LIB_COMPILE, THE_LIB_LINK)

-- Define the source files. When using the glob() function of a sourcepath(),
-- you can filter the list of source files by using the `-` operator and
-- specifying a Lua string.match() filter.
-- Since we're running under Tup's Lua parser, we can always use the `+=`
-- operator for convenient table merging, even if the variable has not been
-- declared yet.
the_lib_src += (THE_LIB.glob("src/*.c") - { "linux_exclusive.c$" })

-- Compile and link the library into a DLL. The rule functions return a table
-- that represents the outputs of this build step as inputs for further steps.
the_lib_obj = the_lib_cfg:cxx(the_lib_src)
the_lib_dll = the_lib_cfg:dll(the_lib_obj, "the_lib")
-- -----------------------------

-- Define the project itself.
PROJECT = sourcepath("src_of_project/")

-- The project uses C++23 Standard Library Modules (`import std;`). Compile the
-- `std` module with the basic settings and store the compilation flags
-- necessary to use it. This automatically enables support for the latest C++
-- language standard version.
local modules_cfg = CONFIG:cxx_std_modules()

-- Since we don't need our flags anywhere else, we just inline the table.
project_cfg = CONFIG:branch(modules_cfg, config_h, THE_LIB_LINK, {
	cflags = {
		("-I" .. PROJECT.root),
		"/source-charset:utf-8",
		"/execution-charset:utf-8",
	},
	objdir = "project/",
})

project_src += PROJECT.glob("*.cpp")

-- Turn the `USERNAME` environment variable into a C macro named `BUILDER` and
-- write its value to a header file. If the environment variable and macro name
-- were identical, you can use EnvHeader() as a shorthand that doesn't require
-- tup.import().
tup.import("USERNAME")
project_src.extra_inputs += Header("obj/config.h", {
	BUILDER = (USERNAME .. ""),
})
-- project_src.extra_inputs += EnvHeader("obj/config.h", { BUILDER })

-- Right now, rule function outputs must be merged using `+`, not `+=`.
project_obj = (
	project_cfg:cxx(project_src) +
	project_cfg:rc(PROJECT.join("windows_resource.rc"))
)

project_cfg:exe((project_obj + the_lib_dll), "project")
```

### Interacting with pkg-config

Tup supports command substitution in rules, but this is a bad fit for pkg-config for two reasons:

1. pkg-config would run once per rule
2. Since the Lua script runs before any rule is executed, Tupfiles can't make decisions based on command output. But doing so would be required to e.g. fall back from system libraries to vendored ones.

Therefore, it makes more sense to run pkg-config in a shell script surrounding the Tupfile.
The `pkg_config_env.sh` helper script provides a function that redirects the pkg-config output into environment variables that can later be used with the `EnvConfig()` Lua function:

`build.sh`:

```sh
#!/bin/sh
. ./vendor/tupblocks/pkg_config_env.sh
pkg_config_env_optional zlib
pkg_config_env_required sdl2
tup
```

`Tupfile.lua`:

```lua
-- A function to build a locally vendored zlib in case we can't link to a
-- system-wide installation.
function BuildZLib(base_cfg)
	local ZLIB = sourcepath("vendor/zlib/")

	---@type ConfigShape
	local link = { cflags = ("-I" .. ZLIB.root) }
	local cfg = base_cfg:branch(link)
	link.linputs = cfg:cc(ZLIB.glob("*.c"))
	return link
end

-- Try to create a ConfigShape that represents the system-wide zlib, and fall
-- back onto the vendored one if pkg-config couldn't find it.
local ZLIB_LINK = (EnvConfig("zlib") or BuildZLib(CONFIG))

-- SDL 2 must be installed via pkg-config.
local SDL2_LINK = EnvConfig("sdl2")
```

### Customizing flags from outside the script

The `CONFIG.cflags` and `CONFIG.lflags` tables start out with the contents of the `CFLAGS` and `LFLAGS` environment variables, respectively.
