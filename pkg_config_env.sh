#!/bin/sh

# Redirects pkg-config output into environment variables for use with the
# tupblocks EnvConfig() function.
pkg_config_env() {
	missing=false
	for arg in "$@"; do
		if pkg-config --exists "$arg"; then
			export "${arg}"_cflags="$(pkg-config --cflags "$arg")";
			export "${arg}"_lflags="$(pkg-config --libs "$arg")";
		else
			>&2 printf "$error_prefix '%s' not available via pkg-config\033[0m\n" "$arg"
			unset "${arg}"_cflags
			unset "${arg}"_lflags
			missing=true
		fi
	done
	[ "$missing|$fail_if_missing" = "true|true" ] && exit 1
}

pkg_config_env_required() {
	error_prefix="\033[0;31m❌ Required dependency"
	fail_if_missing=true
	pkg_config_env "$@"
}

pkg_config_env_optional() {
	error_prefix="\033[0;33m⚠️ Optional dependency"
	fail_if_missing=false
	pkg_config_env "$@"
}
