#!/bin/bash
# Copyright 1999-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

. /sbin/functions.sh || exit 1

if [[ ${EUID} -ne 0 ]] ; then
	eerror "$0: must be root."
	exit 1
fi

usage() {
echo "usage: env-update.sh

note:
      This utility generates /etc/profile.env and /etc/csh.env
      from the contents of /etc/env.d/
"
	exit 1
}

export SVCDIR=${svcdir}

# Only update if files have actually changed
if [[ $1 == "-u" ]] ; then
	is_older_than "${svcdir}/envcache" /etc/env.d && exit 0
	shift
fi

if [[ $# -ne 0 ]] ; then
	usage
else
	awk \
		-f /lib/rcscripts/awk/functions.awk \
		-f /lib/rcscripts/awk/genenviron.awk
fi


# vim:ts=4
