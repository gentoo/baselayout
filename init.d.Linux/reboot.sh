# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# In certain VServer configurations we don't have an init process ..
# so we just force a reboot, the utils on the host take care of everything else
if [[ ! -e /dev/initctl ]] && is_vps_sys ; then
    /sbin/reboot -f
    exit 0
fi

opts="-dpk"
[[ ${RC_DOWN_INTERFACE} == "yes" ]] && opts="${opts}i"

/sbin/reboot "${opts}"

# hmm, if the above failed, that's kind of odd ...
# so let's force a reboot
/sbin/reboot -f
