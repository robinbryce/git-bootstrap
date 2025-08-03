#!/bin/sh

# This script is used to clone and checkout initial git repositories.
# Any sophisticated automation or tooling should live in those repositories.

: "${ENV_SCOPE:=.bootstrap}"
export ENV_SCOPE

print_help() {
	cat <<EOF
Usage: $0 <command> [args...]

clone and or checkout git repositories at specific tag, branch or commit

Commands:
  clone <operate-in-dir>
  checkout <operate-in-dir>
  parse_checkout <line>
Options:
  -h               Show this help message

This script uses the environment from the .env.bootstrap file found in <operate-in-dir>

Set the ENV_SCOPE environment variable to override the .bootstrap substring and source a different name

To configure repositories to clone, create a variable
{{.PROJECT_PREFIX}}_GIT_CLONES_SSH in your environment (typically in .env.bootstrap).

To configure tags to checkout, create a variable
{{.PROJECT_PREFIX}}_GIT_CHECKOUTS in your environment (typically in .env.bootstrap).

The following control is offered by {{.PROJECT_PREFIX}}_GIT_CLONES_SSH:
- Clone a repository with a specific clone directory name by appending '#' to
  the repository URL

Example entries:
- plain clone: git@github.com:org/repo.git  
- clone with directory: git@github.com:tenetxyz/mud.git#tenetxyz-mud

The following control is offered by {{.PROJECT_PREFIX}}_GIT_CHECKOUTS:
- Checkout a specific tag by appending '@' to the clone directory name

Example entries:
- git@github.com:latticexyz/mud.git@v.1.2.3 - checkout a specific tag or commit
- git@github.com:latticexyz/mud.git#foo@v.1.2.3 - checkout a specific tag or commit when an explicit clone directory was used
- git@github.com:latticexyz/mud.git^v.1.2.3 - checkout a specific branch, this works with the #foo syntax as well (as above)

Note that tags and branches can contain the special characters, as only the first @ # or ^ is used to split

Example env vars with all features:

{{.PROJECT_PREFIX}}_GIT_CLONES_SSH="\\
  git@github.com:latticexyz/phaserx.git \\
  git@github.com:latticexyz/phaserx.git@v1.2.3 \\
  git@github.com:latticexyz/mud.git#latticexyz-mud \\
  git@github.com:latticexyz/mud.git#latticexyz-mud@create-mud@2.2.14 \\
  "

{{.PROJECT_PREFIX}}_GIT_CHECKOUT="\\
  git@github.com:latticexyz/phaserx.git \\
  git@github.com:latticexyz/phaserx.git@v1.2.3 \\
  git@github.com:latticexyz/mud.git#latticexyz-mud \\
  git@github.com:latticexyz/mud.git#latticexyz-mud@create-mud@2.2.14 \\
  "
EOF
}

env_setup() {
	op_dir=$(realpath "$1")

	env_file=".env${ENV_SCOPE}"
	[ -f "$op_dir/$env_file" ] && . "$op_dir/$env_file"

	env_file=".env${ENV_SCOPE}.secrets"
	[ -f "$op_dir/$env_file" ] && . "$op_dir/$env_file"

	: "${PROJECT_PREFIX:=$(basename -- "$op_dir")}"
	PROJECT_PREFIX=$(printf '%s\n' "$PROJECT_PREFIX" | tr '-' '_' | tr '[:lower:]' '[:upper:]')
}

dirs() {
	env_setup "$1"
	cd "$op_dir" || exit 1

	eval "checkout_var=\$${PROJECT_PREFIX}_GIT_CLONES_SSH"
	dir_list=""

	for item in $checkout_var; do
		name=$(basename "${item%.git}")
		repo=${item%%#*}
		clone_dir=${item#*#}
		[ "$repo" = "$clone_dir" ] && clone_dir="$name"
		dir_list="$dir_list $clone_dir"
	done
	echo "$dir_list"
}

clone() {
	env_setup "$1"
	echo "Cloning repositories in $op_dir"
	cd "$op_dir" || exit 1

	eval "checkout_var=\$${PROJECT_PREFIX}_GIT_CLONES_SSH"

	for item in $checkout_var; do
		name=$(basename "${item%.git}")
		repo=${item%%#*}
		clone_dir=${item#*#}
		[ "$repo" = "$clone_dir" ] && clone_dir="$name"

		if [ -d "$clone_dir" ]; then
			echo "$item already cloned $item, delete manually to re-clone"
		else
			git clone "$repo" "$clone_dir"
		fi
	done
}

checkout() {
	env_setup "$1"
	echo "Checking out repositories in $op_dir"
	cd "$op_dir" || exit 1

	eval "checkout_var=\$${PROJECT_PREFIX}_GIT_CHECKOUTS"

	for item in $checkout_var; do
		checkout_line=$(parse_checkout "$item")

		case "$checkout_line" in
		NOOP\ * | ERR\ *)
			echo "$checkout_line"
			;;
		CHECKOUT\ *)
			tokens=${checkout_line#* }
			dir=${tokens%%[[:space:]]*}
			[ -d "$dir" ] || {
				echo "Target dir: $dir for repo checkout: $checkout_line does not exist"
				continue
			}

			cd "$dir" || exit 1

			if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
				echo "DIRTY dir: $dir < $checkout_line"
			else
				tokens=${tokens#* }
				git checkout "$tokens"
			fi
			cd "$op_dir" || exit 1
			;;
		*)
			echo "Unrecognized line: $checkout_line" >&2
			;;
		esac
	done
}

parse_checkout() {
	line=$1
	orig_item=$1
	item=${orig_item#*@}
	has_dir=${item#*#}
	has_at=${item#*@}
	has_branch=${item#*^}

	case "$item" in
	*[@^]*) ;;
	*)
		echo "NOOP $orig_item"
		return 0
		;;
	esac

	if [ "$has_dir" = "$item" ]; then
		dir=$(basename "${item%%[@^]*}")
		dir=${dir%.git}
	else
		dir=${has_dir%%[@^]*}
	fi

	at_len=$(expr "x$has_at" : 'x.*')
	branch_len=$(expr "x$has_branch" : 'x.*')

	if [ "$at_len" -lt "$branch_len" ]; then
		echo "CHECKOUT $dir $has_at"
	else
		echo "CHECKOUT $dir $has_branch"
	fi
}

main() {
	if [ "$#" -eq 0 ]; then
		echo "Error: No command provided." >&2
		print_help
		exit 1
	fi

	command=$1
	shift

	case "$command" in
	-h)
		print_help
		exit 0
		;;
	env_setup)
		env_setup "$@"
		;;
	clone)
		clone "$@"
		;;
	checkout)
		checkout "$@"
		;;
	dirs)
		dirs "$@"
		;;
	parse_checkout)
		parse_checkout "$@"
		;;
	*)
		echo "Error: Unknown command '$command'" >&2
		print_help
		exit 1
		;;
	esac
}

main "$@"
