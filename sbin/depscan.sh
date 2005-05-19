#!/bin/bash
# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header$

source /etc/init.d/functions.sh

if [[ ! -d ${svcdir} ]]; then
	if ! mkdir -p -m 0755 "${svcdir}" 2>/dev/null ; then
		eerror "Could not create needed directory '${svcdir}'!"
	fi
fi

for x in softscripts snapshot options \
	started starting inactive stopping failed \
	exclusive exitcodes ; do
	if [[ ! -d "${svcdir}/${x}" ]]; then
		if ! mkdir -p -m 0755 "${svcdir}/${x}" 2>/dev/null ; then
			eerror "Could not create needed directory '${svcdir}/${x}'!"
		fi
	fi
done

# Only update if files have actually changed
update=1
if [[ $1 == "-u" ]]; then
	update=0
	for config in /etc/conf.d /etc/init.d /etc/rc.conf
	do
		if [[ ${config} -nt "${svcdir}/depcache" ]]; then
			update=1
			break
		fi
	done
	shift
fi
[[ ${update} == 0 ]] && exit 0

ebegin "Caching service dependencies"

# Clean out the non volitile directories ...
rm -rf "${svcdir}"/dep{cache,tree} "${svcdir}"/{broken,snapshot}/*

retval=0
SVCDIR="${svcdir}"
DEPTYPES="${deptypes}"
ORDTYPES="${ordtypes}"

export SVCDIR DEPTYPES ORDTYPES

cd /etc/init.d

/bin/gawk \
	-f /lib/rcscripts/awk/functions.awk \
	-f /lib/rcscripts/awk/cachedepends.awk || \
	retval=1

bash "${svcdir}/depcache" | \
/bin/gawk \
	-f /lib/rcscripts/awk/functions.awk \
	-f /lib/rcscripts/awk/gendepends.awk || \
	retval=1

touch -m "${svcdir}"/dep{cache,tree}

eend ${retval} "Failed to cache service dependencies"

exit ${retval}

# vim:ts=4
