#!/bin/bash
# Copyright 1999-2003 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# Author: Martin Schlemmer <azarah@gentoo.org>
# $Header$

# RC Dependency and misc service functions


export RC_GOT_SERVICES="yes"

[ "${RC_GOT_FUNCTIONS}" != "yes" ] && source /sbin/functions.sh
[ "${RC_GOT_DEPTREE_INFO}" != "yes" ] && source "${svcdir}/deptree"

if [ "${RC_GOT_DEPTREE_INFO}" != "yes" ]
then
	eerror "Dependency info is missing!  Please run"
	echo
	eerror "  # /sbin/depscan.sh"
	echo
	eerror "to fix this."
fi


# bool get_dep_info(service)
#
#   Set the Dependency variables to contain data for 'service'
#
get_dep_info() {
	[ -z "$1" ] && return 1

	# We already have the right stuff ...
	[ "${rc_name}" = "$1" ] && return 0
	
	# If no 'depinfo_$1' function exist, then we have problems.
	[ -z "$(declare -F "depinfo_$1")" ] && return 1

	"depinfo_$1"

	return 0
}

# string check_dependency(deptype, service1)
#
#   List all the services that depend on 'service1' of dependency
#   type 'deptype'
#
# bool check_dependency(deptype, -t, service1, service2)
#
#   Returns true if 'service2' is a dependency of type 'deptype'
#   of 'service1'
#
check_dependency() {
	local x=

	[ -z "$1" -o -z "$2" ] && return 1
	
	# Set the dependency variables to relate to 'service1'
	if [ "$2" = "-t" ]
	then
		[ -z "$3" -o -z "$4" ] && return 1

		get_dep_info "$3" &>/dev/null || return 1
	else
		get_dep_info "$2" &>/dev/null || return 1
	fi

	# Do we have valid info for 'deptype' ?
	[ -z "$(eval echo \${rc_$1})" ] && return 1

	if [ "$2" = "-t" -a -n "$4" ]
	then
		# Check if 'service1' have 'deptype' dependency on 'service2'
		for x in $(eval echo \${rc_$1})
		do
			[ "${x}" = "$4" ] && return 0
		done
	else
		# Just list all services that 'service1' have 'deptype' dependency on.
		eval echo "\${rc_$1}"

		return 0
	fi

	return 1
}

# Same as for check_dependency, except 'deptype' is set to
# 'ineed'.  It will return all the services 'service1' NEED's.
ineed() {
	[ -z "$1" ] && return 1
	
	check_dependency ineed $*
	
	return $?
}

# Same as for check_dependency, except 'deptype' is set to
# 'needsme'.  It will return all the services that NEED 'service1'.
needsme() {
	[ -z "$1" ] && return 1
	
	check_dependency needsme $*

	return $?
}

# Same as for check_dependency, except 'deptype' is set to
# 'iuse'.  It will return all the services 'service1' USE's.
iuse() {
	[ -z "$1" ] && return 1
	
	check_dependency iuse $*

	return $?
}

# Same as for check_dependency, except 'deptype' is set to
# 'usesme'.  It will return all the services that USE 'service1'.
usesme() {
	[ -z "$1" ] && return 1
	
	check_dependency usesme $*

	return $?
}

# Same as for check_dependency, except 'deptype' is set to
# 'ibefore'.  It will return all the services that are started
# *after* 'service1' (iow, it will start 'service1' before the
# list of services returned).
ibefore() {
	[ -z "$1" ] && return 1
	
	check_dependency ibefore $*

	return $?
}

# Same as for check_dependency, except 'deptype' is set to
# 'iafter'.  It will return all the services that are started
# *before* 'service1' (iow, it will start 'service1' after the
# list of services returned).
iafter() {
	[ -z "$1" ] && return 1
	
	check_dependency iafter $*

	return $?
}

# bool iparallel(service)
#
#   Returns true if the service can be started in parallel.
#
iparallel() {
	[ -z "$1" ] && return 1

	if check_dependency parallel -t "$1" "no"
	then
		return 1
	fi

	return 0
}

# bool service_started(service)
#
#   Returns true if 'service' is started
#
service_started() {
	[ -z "$1" ] && return 1
	
	if [ -L "${svcdir}/started/$1" ]
	then
		return 0
	fi

	return 1
}

# bool in_runlevel(service, runlevel)
#
#   Returns true if 'service' is in runlevel 'runlevel'.
#
in_runlevel() {
	[ -z "$1" -o -z "$2" ] && return 1

	[ -L "/etc/runlevels/$2/$1" ] && return 0

	return 1
}

# bool runlevel_start()
#
#   Returns true if it is a runlevel change, and we are busy
#   starting services.
#
runlevel_start() {
	[ -d "${svcdir}/softscripts.old" ] && return 0

	return 1
}

# bool runlevel_stop()
#
#   Returns true if it is a runlevel change, and we are busy
#   stopping services.
#
runlevel_stop() {
	[ -d "${svcdir}/softscripts.new" ] && return 0

	return 1
}

# int start_service(service)
#
#   Start 'service' if it is not already running.
#
start_service() {
	local retval=0
	
	[ -z "$1" ] && return 1
	
	if ! service_started "$1"
	then
		(. /sbin/runscript.sh "/etc/init.d/$1" start)
		retval=$?
		
		wait
		
		return "${retval}"
	fi

	return 0
}

# int stop_service(service)
#
#   Stop 'service' if it is not already running.
#
stop_service() {
	local retval=0
	
	[ -z "$1" ] && return 1

	if service_started "$1" 
	then
		(. /sbin/runscript.sh "/etc/init.d/$1" stop)
		retval=$?
		
		wait
		
		return "${retval}"
	fi

	return 0
}

# void schedule_service_startup(service)
#
#   Schedule 'service' for startup, in parallel if possible.
#
schedule_service_startup() {
	local count=0

	if [ "${RC_PARALLEL_STARTUP}" = "yes" ]
	then
		set -m +b

		if [ "$(jobs | grep -c "Running")" -gt 0 ]
		then
			if [ "$(jobs | grep -c "Running")" -eq 1 ]
			then
				# Wait if we cannot start this service with the already running
				# one (running one might start this one ...).
				query_before "$1" "$(jobs | awk '/Running/ { print $4}')" && wait

			elif [ "$(jobs | grep -c "Running")" -ge 2 ]
			then
				count="$(jobs | grep -c "Running")"

				# Wait until we have only one service running
				while [ "${count}" -gt 1 ]
				do
					count="$(jobs | grep -c "Running")"
				done

				# Wait if we cannot start this service with the already running
				# one (running one might start this one ...).
				query_before "$1" "$(jobs | awk '/Running/ { print $4}')" && wait
			fi
		fi

		if iparallel "$1"
		then		
			eval start_service "$1" \&
		else
			# Do not start with any service running if we cannot start
			# this service in parallel ...
#			wait

			start_service "$1"
		fi
	else
		start_service "$1"
	fi

	# We do not need to check the return value here, as svc_{start,stop}() do
	# their own error handling ...
	return 0
}

# bool dependon(service1, service2)
#
#   Does service1 depend (NEED or USE) on service2 ?
#
dependon() {
	[ -z "$1" -o -z "$2" ] && return 1
	
	if ineed -t "$1" "$2" || iuse -t "$1" "$2"
	then
		return 0
	fi

	return 1
}

# string valid_iuse(service)
#
#   This will only give the valid use's for the service
#   (they must be in the boot or current runlevel)
#
valid_iuse() {
	local x=
	local y=

	for x in $(iuse "$1")
	do
		if [ -e "/etc/runlevels/boot/${x}" -o \
		     -e "/etc/runlevels/${mylevel}/${x}" ]
		then
			echo "${x}"
		fi
	done

	return 0
}

# string valid_iafter(service)
#
#   Valid services for current or boot rc level that should start
#   before 'service'
#
valid_iafter() {
	local x=
	
	for x in $(iafter "$1")
	do
		if [ -e "/etc/runlevels/boot/${x}" -o \
		     -e "/etc/runlevels/${mylevel}/${x}" ]
		then
			echo "${x}"
		fi
	done

	return 0
}

# List broken dependencies of type 'need'
broken() {
	local x=
	
	if [ -d "${svcdir}/broken/$1" ]
	then
		for x in $(dolisting "${svcdir}/broken/$1/")
		do
			[ ! -f "${x}" ] && continue
			
			echo "${x##*/}"
		done
	fi

	return 0
}

# void trace_depend(deptype, service)
#
#   Trace the dependency tree of 'service' for type 'deptype', and
#   modify QSERVICE_LIST with the info.
#
#   NOTE:  You should 'declare -x QSERVICE_LIST=' in the function
#          that calls this one ...
#
trace_depend() {
	local deps=
	local x=
	local y=
	local add=

	[ -z "$1" -o -z "$2" ] && return 1
	
	# Build the list of services that 'deptype' on this one
	for x in $("$1" "$2")
	do
		add="yes"
		
		for y in ${QSERVICE_LIST}
		do
			[ "${x}" = "${y}" ] && add="no"
		done

		[ "${add}" = "yes" ] && export QSERVICE_LIST="${QSERVICE_LIST} ${x}"
		
		# Recurse to build a complete list ...
		trace_depend "$1" "${x}"
	done

	return 0
}

# string list_depend_trace(deptype)
#
#   Return resulting list of services for a trace of
#   type 'deptype' for $myservice
#
list_depend_trace() {
	local x=
	declare -x QSERVICE_LIST=

	[ -z "$1" ] && return 1
	
	trace_depend "$1" "${myservice}"

	for x in ${QSERVICE_LIST}
	do
		echo "${x}"
	done

	return 0
}

# bool query_before(service1, service2)
#
#   Return true if 'service2' should be started *before*
#   service1.
#
query_before() {
	local x=
	declare -x QSERVICE_LIST=

	[ -z "$1" -o -z "$2" ] && return 1

	for x in ineed iuse iafter
	do
		trace_depend "${x}" "$1"
	done
	
	for x in ${QSERVICE_LIST}
	do
		[ "${x}" = "$2" ] && return 0
	done

	return 1
}

# bool query_after(service1, service2)
#
#   Return true if 'service2' should be started *after*
#   service1.
#
query_after() {
	local x=
	declare -x QSERVICE_LIST=

	[ -z "$1" -o -z "$2" ] && return 1

	for x in needsme usesme ibefore
	do
		trace_depend "${x}" "$1"
	done

	for x in ${QSERVICE_LIST}
	do
		[ "${x}" = "$2" ] && return 0
	done

	return 1
}


# vim:ts=4
