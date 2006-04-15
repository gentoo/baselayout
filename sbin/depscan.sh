#!/bin/bash
# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header$

source /etc/init.d/functions.sh

mysvcdir="${svcdir}"
update=false

while [[ -n $1 ]] ; do
	case "$1" in
		--debug|-d)
			set -x
			;;
		--svcdir|-s)
			if [[ -z $2 || $2 == -* ]] ; then
				eerror "No svcdir specified"
			else
				shift
				mysvcdir="$1"
			fi
			;;
		--update|-u)
			update=true
			;;
	esac
	shift
done

if [[ ! -d ${mysvcdir} ]] ; then
	if ! mkdir -p -m 0755 "${mysvcdir}" 2>/dev/null ; then
		eerror "Could not create needed directory '${mysvcdir}'!"
	fi
fi

for x in softscripts snapshot options started ; do
	if [[ ! -d "${mysvcdir}/${x}" ]] ; then
		if ! mkdir -p -m 0755 "${mysvcdir}/${x}" 2>/dev/null ; then
			eerror "Could not create needed directory '${mysvcdir}/${x}'!"
		fi
	fi
done

# Only update if files have actually changed
if ! ${update} ; then
	# If its not there, we have to update, and make sure its present
	# for next mtime testing
	if [[ ! -e "${mysvcdir}/depcache" ]] ; then
			update=true
			touch "${mysvcdir}/depcache"
	fi

	for config in /etc/conf.d /etc/init.d /etc/rc.conf
	do
		! ${update} \
			&& is_older_than "${mysvcdir}/depcache" "${config}" \
			&& update=true
	done
fi

! ${update} && exit 0

ebegin "Caching service dependencies"

# Clean out the non volatile directories ...
rm -rf "${mysvcdir}"/dep{cache,tree} "${mysvcdir}"/{broken,snapshot}/*

retval=0
SVCDIR="${mysvcdir}"
DEPTYPES="${deptypes}"
ORDTYPES="${ordtypes}"

export SVCDIR DEPTYPES ORDTYPES

cd /etc/init.d

/bin/gawk \
	-f /lib/rcscripts/awk/functions.awk \
	-f /lib/rcscripts/awk/cachedepends.awk || \
	retval=1

bash "${mysvcdir}/depcache" | \
/bin/gawk \
	-f /lib/rcscripts/awk/functions.awk \
	-f /lib/rcscripts/awk/gendepends.awk || \
	retval=1

touch "${mysvcdir}"/dep{cache,tree}
chmod 0644 "${mysvcdir}"/dep{cache,tree}

eend ${retval} "Failed to cache service dependencies"

exit ${retval}

# vim:ts=4
