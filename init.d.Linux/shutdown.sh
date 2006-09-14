# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

[[ ${INIT_HALT} != "HALT" ]] && opts="${opts}p"
if [[ $(uname) == "Linux" ]] ; then
	opts="-d"
	[[ ${RC_DOWN_INTERFACE} == "yes" ]] && opts="${opts}i"
	[[ ${RC_DOWN_HARDDISK} == "yes" ]] && opts="${opts}h"
fi

/sbin/halt "${opts}"

# hmm, if the above failed, that's kind of odd ...
# so let's force a halt
/sbin/halt -f
