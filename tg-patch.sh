#!/bin/sh
# TopGit - A different patch queue manager
# (c) Petr Baudis <pasky@suse.cz>  2008
# GPLv2

name=

head_from=
diff_opts=
diff_committed_only=yes	# will be unset for index/worktree


## Parse options

while [ -n "$1" ]; do
	arg="$1"; shift
	case "$arg" in
	-i)
		[ -z "$head_from" ] || die "-i and -w are mutually exclusive"
		head_from=-i
		diff_opts="$diff_opts --cached";
		diff_committed_only=;;
	-w)
		[ -z "$head_from" ] || die "-i and -w are mutually exclusive"
		head_from=-w
		diff_committed_only=;;
	-*)
		echo "Usage: tg [...] patch [-i | -w] [NAME]" >&2
		exit 1;;
	*)
		[ -z "$name" ] || die "name already specified ($name)"
		name="$arg";;
	esac
done

head="$(git symbolic-ref HEAD)"
head="${head#refs/heads/}"

[ -n "$name" ] ||
	name="$head"
base_rev="$(git rev-parse --short --verify "refs/top-bases/$name" 2>/dev/null)" ||
	die "not a TopGit-controlled branch"

if [ -n "$head_from" ] && [ "$name" != "$head" ]; then
	die "$head_from makes only sense for the current branch"
fi



setup_pager

cat_file "$name:.topmsg" $head_from
echo
[ -n "$(git grep $diff_opts '^[-]--' ${diff_committed_only:+"$name"} -- ".topmsg")" ] || echo '---'

# Evil obnoxious hack to work around the lack of git diff --exclude
git_is_stupid="$(get_temp tg-patch-changes)"
git diff --name-only $diff_opts "$base_rev" ${diff_committed_only:+"$name"} -- |
	fgrep -vx ".topdeps" |
	fgrep -vx ".topmsg" >"$git_is_stupid" || : # fgrep likes to fail randomly?
if [ -s "$git_is_stupid" ]; then
	cd "$root_dir"
	cat "$git_is_stupid" | xargs git diff -a --patch-with-stat $diff_opts "$base_rev" ${diff_committed_only:+"$name"} --
else
	echo "No changes."
fi

echo '-- '
echo "tg: ($base_rev..) $name (depends on: $(cat_file "$name:.topdeps" $head_from | paste -s -d' '))"
branch_contains "$name" "$base_rev" ||
	echo "tg: The patch is out-of-date wrt. the base! Run \`$tg update\`."

# vim:noet
