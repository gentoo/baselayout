#!/bin/bash
# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# Author:  Martin Schlemmer <azarah@gentoo.org>
# $Header$


source /etc/init.d/functions.sh

if [ `id -u` -ne 0 ]
then
	eerror "$0: must be root."
	exit 1
fi

usage() {
cat << FOO
usage: rc-envupdate.sh

note:
      This utility generates /etc/profile.env and /etc/csh.env
      from the contents of /etc/env.d/

FOO
	exit 1
}
		
if [ "$#" -ne 0 ]
then
	usage
else
	/bin/gawk -v SVCDIR="/mnt/.init.d" \
		-f /lib/rcscripts/awk/functions.awk \
		-f /lib/rcscripts/awk/genenviron.awk
fi


# vim:ts=4
