# Copyright 1999-2005 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

/sbin/reboot -idp

# hmm, if the above failed, that's kind of odd ...
# so let's force a reboot
/sbin/reboot -f
