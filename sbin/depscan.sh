#!/bin/bash
# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License, v2
# Author:  Martin Schlemmer <azarah@gentoo.org>
# $Header$

source /etc/init.d/functions.sh

ebegin "Caching service dependencies"

/bin/gawk -v SVCDIR="${svcdir}" \
	-f /lib/rcscripts/awk/cachedepends.awk \
	$(find /etc/init.d/ -type f -maxdepth 1)

cd /etc/init.d

bash ${svcdir}/depcache | \
	/bin/gawk -v SVCDIR="${svcdir}" \
		-v DEPTYPES="${deptypes}" \
		-v ORDTYPES="${ordtypes}" \
		-f  /lib/rcscripts/awk/gendepends.awk

eend 0

