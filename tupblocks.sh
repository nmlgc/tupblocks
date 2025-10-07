#!/bin/sh

# Detects the toolchain by querying the tool from the environment variable
# `$1`, falling back on `$2` if it's not set. Returns with the environment
# variable `TOOLCHAIN` set to the tupblocks toolchain identifier, and exits on
# failure.
toolchain_detect() {
	eval "TOOL=\"\${$1:-$2}\""
	read -r version_line <<EOF
	$($TOOL --version)
EOF
	case "$version_line" in
		*GCC*)
			TOOLCHAIN_NEW=gcc;;
		*clang*)
			TOOLCHAIN_NEW=clang;;
		*)
			>&2 printf "\033[0;31m❌ Unable to detect toolchain from '%s' \033[0m\n" "$TOOL"
			exit 1;
	esac
	[ -n "$TOOLCHAIN" ] &&
		[ "$TOOLCHAIN" != "$TOOLCHAIN_NEW" ] &&
		>&2 printf "\033[0;31m❌ Toolchain mismatch: '%s' vs. '%s'\033[0m\n" "$TOOLCHAIN" "$TOOLCHAIN_NEW" &&
		exit 1
	export TOOLCHAIN="$TOOLCHAIN_NEW"
}

toolchain_detect_via_cc() {
	toolchain_detect "CC" "cc"
}

toolchain_detect_via_cxx() {
	toolchain_detect "CXX" "c++"
}

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
