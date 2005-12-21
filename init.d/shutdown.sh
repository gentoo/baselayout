# Copyright 1999-2005 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

opts="-hdp"
[[ ${RC_DOWN_INTERFACE} == "yes" ]] && opts="${opts}i"

/sbin/halt "${opts}"

# hmm, if the above failed, that's kind of odd ...
# so let's force a halt
/sbin/halt -f
