#!/bin/bash
# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header$

source /etc/init.d/functions.sh

if [ "${EUID}" -ne 0 ]
then
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

export SVCDIR="${svcdir}"

# Only update if files have actually changed
update=1
if [ "$1" == "-u" ]
then
	update=0
	for config in /etc/env.d
	do
		if [ "${config}" -nt "${svcdir}/envcache" ]
		then
			update=1
			break
		fi
	done
	shift
fi
[ ${update} -eq 0 ] && exit 0

if [ "$#" -ne 0 ]
then
	usage
else
	/bin/gawk \
		-f /lib/rcscripts/awk/functions.awk \
		-f /lib/rcscripts/awk/genenviron.awk
fi


# vim:ts=4
