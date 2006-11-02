# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# In certain VServer configurations we don't have an init process ...
# so we just exit here, the utils on the host take care of everything else
[[ ! -e /dev/initctl ]] && is_vps_sys && exit 0

opts="-d"
[[ ${INIT_HALT} != "HALT" ]] && opts="${opts}p"
[[ ${RC_DOWN_INTERFACE} == "yes" ]] && opts="${opts}i"
[[ ${RC_DOWN_HARDDISK} == "yes" ]] && opts="${opts}h"

/sbin/halt "${opts}"

# hmm, if the above failed, that's kind of odd ...
# so let's force a halt
/sbin/halt -f
