#!/bin/bash
# Copyright 1999-2003 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# Author:  Martin Schlemmer <azarah@gentoo.org>
# $Header$

source /etc/init.d/functions.sh

ebegin "Caching service dependencies"

if [ ! -d "${svcdir}" ]
then
	if ! install -d -m0755 "${svcdir}" 2>/dev/null
	then
		eerror " Could not create needed directory '${svcdir}'!"
	fi
fi

for x in ${svcdir} softscripts snapshot options started
do
	if [ ! -d "${x}" ]
	then
		if ! install -d -m0755 "${svcdir}/${x}" 2>/dev/null
		then
			eerror " Could not create needed directory '${svcdir}/${x}'!"
		fi
	fi
done

# Clean out the non volitile directories ...
rm -rf ${svcdir}/{broken,snapshot}/*

cd /etc/init.d

if [ "${RC_DEBUG}" = "yes" ]
then
	/bin/gawk -v SVCDIR="${svcdir}" \
		-f /lib/rcscripts/awk/functions.awk \
		-f /lib/rcscripts/awk/cachedepends.awk \
		> "${svcdir}/depcache"
fi

/bin/gawk -v SVCDIR="${svcdir}" \
	-f /lib/rcscripts/awk/functions.awk \
	-f /lib/rcscripts/awk/cachedepends.awk \
\
| bash | \
\
/bin/gawk -v SVCDIR="${svcdir}" \
	-v DEPTYPES="${deptypes}" \
	-v ORDTYPES="${ordtypes}" \
	-f /lib/rcscripts/awk/functions.awk \
	-f /lib/rcscripts/awk/gendepends.awk

eend $? "Failed to cache service dependencies"


# vim:ts=4
