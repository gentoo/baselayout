# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

case $(uname -s) in
	Linux | GNU* ) opts="-idk"; forceopts="-f" ;;
esac

/sbin/reboot -p "${opts}"

# hmm, if the above failed, that's kind of odd ...
# so let's force a reboot
/sbin/reboot "${forceopts}"
