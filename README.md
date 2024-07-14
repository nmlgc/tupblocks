# Opinionated building blocks for the Tup build system

[![Code Nutrition: O+ S++ I C E- !PS](http://code.grevit.net:8084/badge/O%2B_S%2B%2B_I_C_E-___!PS)](http://code.grevit.net:8084/facts/O%2B_S%2B%2B_I_C_E-___!PS)

The missing layer between [Tup](https://gittup.org/tup) and your C/C++ compiler binaries, providing opinionated flags for typical debug/release mode settings.
My fourth attempt at writing such a layer, and finally almost not janky.

Currently only supporting Visual Studio compilers on Windows.
*nix support will be added during [the porting process of 秋霜玉 / Shuusou Gyoku](https://github.com/nmlgc/ssg/issues/42).

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
-- into your build tree in another way. This file will also include rule
-- functions for the current build platform, together with default flags for
-- debug and release builds.
tup.include("vendor/tupblocks/Tuprules.lua")

-- Build the third-party library
-- -----------------------------

-- sourcepath() provides convenient helper functions for globbing, filtering,
-- and subdirectory joining.
THE_LIB = sourcepath("vendor/a_thirdparty_library/")

-- Define the flags exclusive to this library, as separate tables. All of these
-- configuration and flag tables follow the `ConfigShape` class declared in
-- `Tuprules.lua`:
--
-- {
-- 	base = { (compiler settings…) },
-- 	buildtypes= {
-- 		debug = { (compiler settings…) },
-- 		release = { (compiler settings…) },
-- 	}
-- }
THE_LIB_COMPILE = {
	base = {
		cflags = { "/DDLL_EXPORT" }, -- required by the library for DLL builds
		objdir = "the_lib/", -- creates a new namespace for object files
	},
	buildtypes = {
		debug = { cflags = { "/DDEBUG" } },

		-- The base CONFIG table uses the /GL flag for Visual Studio release
		-- builds by default, but this library doesn't like it. Merged settings
		-- can also be functions that are applied to the current value, which
		-- we can use to remove the flag using the flag_remove() helper.
		-- Based on a true story:
		--
		-- https://github.com/libsdl-org/SDL/commit/ae7446a9591299eef719f82403c
		release = { cflags = flag_remove("/GL") }
	}
}

-- Flags for linking to the library.
THE_LIB_LINK = {
	base = {
		cflags = { ("-I" .. THE_LIB.join("include/")) },
	},
}

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
the_lib_obj = cxx(the_lib_cfg, the_lib_src)
the_lib_dll = dll(the_lib_cfg, the_lib_obj, "the_lib")
-- -----------------------------

-- Define the project itself.
PROJECT = sourcepath("src_of_project/")

-- Since we don't need our flags anywhere else, we just inline the table.
project_cfg = CONFIG:branch(THE_LIB_LINK, {
	base = {
		-- Flags are stored as tables. Every logical flag should be its own
		-- element, and can consist of multiple space-separated words.
		cflags = {
			"/std:c++latest",
			("/I" .. PROJECT.root),
			"/source-charset:utf-8",
			"/execution-charset:utf-8",
		},
		objdir = "project/",
	},
})

project_src += PROJECT.glob("*.cpp")

-- Right now, rule function outputs must be merged using `+`, not `+=`.
project_obj = (
	cxx(project_cfg, project_src) +
	rc(project_cfg, PROJECT.join("windows_resource.rc"))
)

exe(project_cfg, (project_obj + the_lib_dll), "project")
```
