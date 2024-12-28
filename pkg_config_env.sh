#!/bin/sh

# Redirects pkg-config output into environment variables for use with the
# tupblocks EnvConfig() function.
pkg_config_env() {
	for arg in "$@"; do
		if pkg-config --exists "$arg"; then
			export "${arg}"_cflags="$(pkg-config --cflags "$arg")";
			export "${arg}"_lflags="$(pkg-config --libs "$arg")";
		else
			>&2 printf "\033[0;33m⚠️ %s not available via pkg-config\033[0m\n" "$arg"
			unset "${arg}"_cflags
			unset "${arg}"_lflags
		fi
	done
}
