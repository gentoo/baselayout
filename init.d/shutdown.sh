# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

opts="-p"
case $(uname -s) in
Linux | GNU* )
	opts="${opts}dh"
	forceopts="-f"
	[[ ${RC_DOWN_INTERFACE} == "yes" ]] && opts="${opts}i"
	;;
FreeBSD )
	opts="${opts}l" ;;
esac

/sbin/halt "${opts}"

# hmm, if the above failed, that's kind of odd ...
# so let's force a halt
/sbin/halt "${forceopts}"
