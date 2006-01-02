# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

/sbin/halt -ihdp

# hmm, if the above failed, that's kind of odd ...
# so let's force a halt
/sbin/halt -f
