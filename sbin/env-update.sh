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

if [ "$#" -ne 0 ]
then
	usage
else
	/bin/gawk \
		-f /lib/rcscripts/awk/functions.awk \
		-f /lib/rcscripts/awk/genenviron.awk
fi


# vim:ts=4
