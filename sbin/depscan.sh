#!/bin/bash
# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

source /sbin/functions.sh

if [[ $1 == "--debug" ]] ; then
	shift
	set -x
fi

if [[ ! -d ${svcdir} ]] ; then
	if ! mkdir -p -m 0755 "${svcdir}" 2>/dev/null ; then
		eerror "Could not create needed directory '${svcdir}'!"
	fi
fi

for x in softscripts snapshot options daemons \
	started starting inactive stopping failed \
	exclusive exitcodes restart ; do
	if [[ ! -d "${svcdir}/${x}" ]] ; then
		if ! mkdir -p -m 0755 "${svcdir}/${x}" 2>/dev/null ; then
			eerror "Could not create needed directory '${svcdir}/${x}'!"
		fi
	fi
done

# Only update if files have actually changed
update=1

if [[ $1 == "-u" ]] ; then
	update=0
	clock_screw=0
	mtime_test="${svcdir}/mtime-test.$$"

	# If its not there, we have to update, and make sure its present
	# for next mtime testing
	if [[ ! -e ${svcdir}/depcache ]] ; then
			update=1
			touch "${svcdir}/depcache"
	fi

	touch "${mtime_test}"
	for config in /etc/conf.d /etc/init.d /etc/rc.conf
	do
		[[ ${update} == 0 ]] && \
			is_older_than "${svcdir}/depcache" "${config}" && update=1
		
		is_older_than "${mtime_test}" "${config}" && clock_screw=1
	done
	rm -f "${mtime_test}"

	[[ ${clock_screw} == 1 ]] && \
		ewarn "Some file in '/etc/{conf.d,init.d}' have Modification time in the future!"

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

touch "${svcdir}"/dep{cache,tree}
chmod 0644 "${svcdir}"/dep{cache,tree}

eend ${retval} "Failed to cache service dependencies"

exit ${retval}

# vim:ts=4
