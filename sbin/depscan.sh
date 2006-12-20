#!/bin/bash
# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

if [[ ${BOOT} == "yes" ]] ; then
	trap ":" INT QUIT TSTP
fi

argv0=${0##*/}
. /etc/init.d/functions.sh || {
	echo "${argv0}: Could not source /etc/init.d/functions.sh!" 1>&2
	exit 1
}
esyslog() { :; }

usage() {
	cat <<-EOF
	Usage: ${argv0} [options]

	Rebuild Gentoo init.d service dependency tree.

	Options:
	  -d, --debug       Turn on debug output
	  -s, --svcdir      Specify svcdir (default: ${svcdir})
	  -u, --update      Force update even if mtimes are OK
	  -h, --help        Show this help cruft
	EOF
	[[ -z $@ ]] && exit 0
	echo
	eerror "$*"
	exit 1
}

mysvcdir=${svcdir}
update=false
nupdate=false

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
			nupdate=true
			;;
		--help|-h)
			usage
			;;
		*)
			usage "Invalid option '$1'"
			;;
	esac
	shift
done

if [[ ! -d ${mysvcdir} ]] ; then
	if ! mkdir -p -m 0755 "${mysvcdir}" 2>/dev/null ; then
		eerror "Could not create needed directory '${mysvcdir}'!"
	fi
fi

for x in softscripts snapshot options daemons \
	started starting inactive wasinactive stopping failed \
	exclusive scheduled coldplugged ebuffer ; do
	if [[ ! -d "${mysvcdir}/${x}" ]] ; then
		if ! mkdir -p -m 0755 "${mysvcdir}/${x}" 2>/dev/null ; then
			eerror "Could not create needed directory '${mysvcdir}/${x}'!"
			exit 1
		fi
	fi
done

if [[ ! -w ${mysvcdir} ]] ; then 
	eerror "${mysvcdir} is read-only, cannot update deptree"
	exit 1
fi

check_files() {
	local testfile=$1 clock_skew= f= retval=0
	local mtime_test="${mysvcdir}/mtime-test.$$"
	[[ -e ${testfile} ]] || return 1

	shift
	mtime_test="${mysvcdir}/mtime-test.$$"

	touch "${mtime_test}"

	for f in "$@" ; do
		if [[ ${retval} == 0 ]] ; then
			is_older_than "${testfile}" "${f}" && retval=1
		fi
		if is_older_than "${mtime_test}" "${f}" ; then
			touch "${f}" &>/dev/null
			clock_skew="${clock_skew} ${f}"
		fi
	done

	if [[ -n ${clock_skew} ]] ; then
		ewarn $"These files have future mtimes :-"
		eindent
		for f in ${clock_skew} ; do
			ewarn "${f}"
		done
	fi

	rm -f "${mtime_test}"

	return ${retval}
}

SVCDIR="${mysvcdir}"
SVCLIB="${svclib}"
export SVCDIR SVCLIB

[[ -e "${mysvcdir}/deptree" ]] || update=true
if ! ${update} ; then
	check_files "${mysvcdir}/depcache" /etc/conf.d /etc/init.d \
		/etc/rc.conf || update=true
	if ${!update} ; then
		if ! bash -n "${mysvcdir}/deptree" ; then
			eerror "${mysvcdir}/deptree is not valid - recreating it"
			update=true
		fi
	fi
fi

if ${update} ; then
	ebegin "Caching service dependencies"

	# Clean out the non volatile directories ...
	rm -rf "${mysvcdir}"/{broken,snapshot}/*
	retval=0

	awk \
		-f /lib/rcscripts/awk/functions.awk \
		-f /lib/rcscripts/awk/cachedepends.awk || \
		retval=1

	if [[ ${retval} == "0" ]] ; then
		DEPTREE="deptree"
		export DEPTREE
		cd /etc/init.d
		bash "${mysvcdir}/depcache" | \
			awk \
				-f /lib/rcscripts/awk/functions.awk \
				-f /lib/rcscripts/awk/gendepends.awk || \
				retval=1
	fi

	if [[ ${retval} == "0" ]] ; then
		touch "${mysvcdir}"/dep{cache,tree}
		chmod 0644 "${mysvcdir}"/dep{cache,tree}
	fi

	eend ${retval} "Failed to cache service dependencies"
	[[ ${retval} != "0" ]] && exit ${retval}
fi

[[ -e "${mysvcdir}/netdeptree" ]] || nupdate=true
if ! ${nupdate} ; then
	check_files "${mysvcdir}/netdepcache" "${svclib}"/net || nupdate=true
	if ${!nupdate} ; then
		if ! bash -n "${mysvcdir}/netdeptree" ; then
			eerror "${mysvcdir}/netdeptree is not valid - recreating it"
			nupdate=true
		fi
	fi
fi
if ${nupdate} ; then
	ebegin "Caching network dependencies"
	retval=0

	awk \
		-f /lib/rcscripts/awk/functions.awk \
		-f /lib/rcscripts/awk/cachenetdepends.awk || \
		retval=1

	if [[ ${retval} == "0" ]] ; then
		DEPTREE="netdeptree"
		export DEPTREE
		cd "${svclib}/net"
		bash "${mysvcdir}/netdepcache" | \
			awk \
				-f /lib/rcscripts/awk/functions.awk \
				-f /lib/rcscripts/awk/gendepends.awk || \
				retval=1
	fi

	if [[ ${retval} == "0" ]] ; then
		touch "${mysvcdir}"/netdep{cache,tree}
		chmod 0644 "${mysvcdir}"/netdep{cache,tree}
	fi

	eend ${retval} "Failed to cache network dependencies"
	[[ ${retval} != "0" ]] && exit ${retval}
fi

exit 0

# vim: set ts=4 :
