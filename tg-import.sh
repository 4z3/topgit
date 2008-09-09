#!/bin/sh
# TopGit - A different patch queue manager
# GPLv2


tg_get_commit_msg()
{
	commit="$1"
	git log -1 --pretty=format:"From: %an <%ae>%n%n%s%n%n%b" "$commit"
}

tg_get_branch_name()
{
	# nice sed script from git-format-patch.sh
	commit="$1"
	titleScript='
	s/[^-a-z.A-Z_0-9]/-/g
        s/\.\.\.*/\./g
	s/\.*$//
	s/--*/-/g
	s/^-//
	s/-$//
	q
'
	git log -1 --pretty=format:"%s" "$commit" | sed -e "$titleScript"
}

tg_process_commit()
{
	commit="$1"
	branch_name=$(tg_get_branch_name "$commit")
	echo "Importing $commit to $branch_name"
	tg create tp/"$branch_name"
	git read-tree "$commit"
	tg_get_commit_msg "$commit" > .topmsg
	git add -f .topmsg .topdeps
	git commit -C "$commit"
}

# nice arg verification stolen from git-format-patch.sh
for revpair
do
	case "$revpair" in
	?*..?*)
		rev1=`expr "z$revpair" : 'z\(.*\)\.\.'`
		rev2=`expr "z$revpair" : 'z.*\.\.\(.*\)'`
		;;
	*)
		die "Unknow range spec $revpair"
		;;
	esac
	git rev-parse --verify "$rev1^0" >/dev/null 2>&1 ||
		die "Not a valid rev $rev1 ($revpair)"
	git rev-parse --verify "$rev2^0" >/dev/null 2>&1 ||
		die "Not a valid rev $rev2 ($revpair)"
	git cherry -v "$rev1" "$rev2" |
	while read sign rev comment
	do
		case "$sign" in
		'-')
			info "Merged already: $comment"
			;;
		*)
			tg_process_commit "$rev"
			;;
		esac
	done
done
