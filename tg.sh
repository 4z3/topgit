#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2


## Auxiliary functions

info()
{
	echo "${TG_RECURSIVE}tg: $*"
}

die()
{
	info "fatal: $*"
	exit 1
}

# setup_hook NAME
setup_hook()
{
	hook_call="\"\$(tg --hooks-path)\"/$1 \"\$@\""
	if [ -f "$git_dir/hooks/$1" ] &&
	   fgrep -q "$hook_call" "$git_dir/hooks/$1"; then
		# Another job well done!
		return
	fi
	# Prepare incanation
	if [ -x "$git_dir/hooks/$1" ]; then
		hook_call="$hook_call"' || exit $?'
	else
		hook_call="exec $hook_call"
	fi
	# Insert call into the hook
	{
		echo "#!/bin/sh"
		echo "$hook_call"
		[ ! -s "$git_dir/hooks/$1" ] || cat "$git_dir/hooks/$1"
	} >"$git_dir/hooks/$1+"
	chmod a+x "$git_dir/hooks/$1+"
	mv "$git_dir/hooks/$1+" "$git_dir/hooks/$1"
}

# setup_ours (no arguments)
setup_ours()
{
	if [ ! -s "$git_dir/info/attributes" ] || ! grep -q topmsg "$git_dir/info/attributes"; then
		{
			echo -e ".topmsg\tmerge=ours"
			echo -e ".topdeps\tmerge=ours"
		} >>"$git_dir/info/attributes"
	fi
	if ! git config merge.ours.driver >/dev/null; then
		git config merge.ours.name '"always keep ours" merge driver'
		git config merge.ours.driver 'touch %A'
	fi
}

# measure_branch NAME [BASE]
measure_branch()
{
	_name="$1"; _base="$2"
	[ -n "$_base" ] || _base="refs/top-bases/$_name"
	# The caller should've verified $name is valid
	_commits="$(git rev-list "$_name" ^"$_base" | wc -l)"
	_nmcommits="$(git rev-list --no-merges "$_name" ^"$_base" | wc -l)"
	if [ $_commits -gt 1 ]; then
		_suffix="commits"
	else
		_suffix="commit"
	fi
	echo "$_commits/$_nmcommits $_suffix"
}

# branch_contains B1 B2
# Whether B1 is a superset of B2.
branch_contains()
{
	[ -z "$(git rev-list ^"$1" "$2")" ]
}

# recurse_deps CMD NAME [BRANCHPATH...]
# Recursively eval CMD on all dependencies of NAME.
# CMD can refer to $_name for queried branch name,
# $_dep for dependency name,
# $_depchain for space-seperated branch backtrace,
# and the $_dep_is_tgish boolean.
# It can modify $_ret to affect the return value
# of the whole function.
# If recurse_deps() hits missing dependencies, it will append
# them to space-separated $missing_deps list and skip them.
recurse_deps()
{
	_cmd="$1"; shift
	_name="$1"; # no shift
	_depchain="$*"
	_depsfile="$(mktemp)"
	git cat-file blob "$_name:.topdeps" >"$_depsfile"
	_ret=0
	while read _dep; do
		if ! git rev-parse --verify "$_dep" >/dev/null 2>&1; then
			# All hope is lost
			missing_deps="$missing_deps $_dep"
			continue
		fi

		_dep_is_tgish=1
		git rev-parse --verify "refs/top-bases/$_dep" >/dev/null 2>&1 ||
			_dep_is_tgish=

		# Shoo shoo, keep our environment alone!
		[ -z "$_dep_is_tgish" ] ||
			(needs_update "$_cmd" "$_dep" "$@") ||
			_ret=$?

		eval "$_cmd"
	done <"$_depsfile"
	missing_deps="${missing_deps# }"
	rm "$_depsfile"
	return $_ret
}

# branch_needs_update
# This is a helper function for determining whether given branch
# is up-to-date wrt. its dependencies. It expects input as if it
# is called as a recurse_deps() helper.
# In case the branch does need update, it will echo it together
# with the branch backtrace on the output (see needs_update()
# description for details) and set $_ret to non-zero.
branch_needs_update()
{
	_dep_base_uptodate=1
	if [ -n "$_dep_is_tgish" ]; then
		branch_contains "$_dep" "refs/top-bases/$_dep" || _dep_base_uptodate=
	fi

	if [ -z "$_dep_base_uptodate" ]; then
		# _dep needs to be synced with its base
		echo ": $_dep $_depchain"
		_ret=1
	elif ! branch_contains "refs/top-bases/$1" "$_dep"; then
		# Some new commits in _dep
		echo "$_dep $_depchain"
		_ret=1
	fi
}

# needs_update NAME
# This function is recursive; it outputs reverse path from NAME
# to the branch (e.g. B_DIRTY B1 B2 NAME), one path per line,
# inner paths first. Innermost name can be ':' if the head is
# not in sync with the base.
# It will also return non-zero status if NAME needs update.
# If needs_update() hits missing dependencies, it will append
# them to space-separated $missing_deps list and skip them.
needs_update()
{
	recurse_deps branch_needs_update "$@"
}

# branch_empty NAME
branch_empty()
{
	[ -z "$(git diff-tree "refs/top-bases/$1" "$1" | fgrep -v "	.top")" ]
}

# switch_to_base NAME [SEED]
switch_to_base()
{
	_base="refs/top-bases/$1"; _seed="$2"
	# We have to do all the hard work ourselves :/
	# This is like git checkout -b "$_base" "$_seed"
	# (or just git checkout "$_base"),
	# but does not create a detached HEAD.
	git read-tree -u -m HEAD "${_seed:-$_base}"
	[ -z "$_seed" ] || git update-ref "$_base" "$_seed"
	git symbolic-ref HEAD "$_base"
}

# Show the help messages.
do_help()
{
	if [ -z "$1" ] ; then
		## Build available commands list for help output

		cmds=
		sep=
		for cmd in "@cmddir@"/tg-*; do
			! [ -r "$cmd" ] && continue
			# strip directory part and "tg-" prefix
			cmd="$(basename "$cmd")"
			cmd="${cmd#tg-}"
			cmds="$cmds$sep$cmd"
			sep="|"
		done

		echo "TopGit v0.1 - A different patch queue manager"
		echo "Usage: tg ($cmds|help) ..."
	elif [ -r "@sharedir@/tg-$1.txt" ] ; then
		cat "@sharedir@/tg-$1.txt"
	else
		echo "`basename $0`: no help for $1" 1>&2
	fi
}


## Initial setup

set -e
git_dir="$(git rev-parse --git-dir)"
root_dir="$(git rev-parse --show-cdup)"; root_dir="${root_dir:-.}"
# make sure merging the .top* files will always behave sanely
setup_ours
setup_hook "pre-commit"

[ -d "@cmddir@" ] ||
	die "No command directory: '@cmddir@'"

## Dispatch

# We were sourced from another script for our utility functions;
# this is set by hooks.
[ -z "$tg__include" ] || return 0

cmd="$1"
[ -n "$cmd" ] || die "He took a duck in the face at two hundred and fifty knots"
shift

case "$cmd" in
help|--help|-h)
	do_help "$1"
	exit 1;;
--hooks-path)
	# Internal command
	echo "@hooksdir@";;
*)
	[ -r "@cmddir@"/tg-$cmd ] || {
		echo "Unknown subcommand: $cmd" >&2
		exit 1
	}
	. "@cmddir@"/tg-$cmd;;
esac
