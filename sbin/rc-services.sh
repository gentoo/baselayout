# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header$

# RC Dependency and misc service functions

RC_GOT_SERVICES="yes"

[[ ${RC_GOT_FUNCTIONS} != "yes" ]] && source /sbin/functions.sh

if [[ ${RC_GOT_DEPTREE_INFO} != "yes" ]]; then
	# Only try and update if we are root
	if [[ ${EUID} == "0" ]] && ! /sbin/depscan.sh -u ; then
		echo
		eerror "Error running '/sbin/depscan.sh'!"
		eerror "Please correct any problems above."
		exit 1
	fi

	source "${svcdir}/deptree"
	if [[ ${RC_GOT_DEPTREE_INFO} != "yes" ]]; then
		echo
		eerror "Dependency info is missing!  Please run"
		eerror "  # /sbin/depscan.sh"
		eerror "to fix this."
		exit 1
	fi
fi

#####################
# Internal variables
#####################

# The name of the service whose dependency info we currently have
rc_name=
# The index of the service whose dependency info we currently have
rc_index=0
# Our dependency types ...
rc_ineed=
rc_needsme=
rc_iuse=
rc_usesme=
rc_ibefore=
rc_iafter=
rc_broken=
rc_parallel=
rc_mtime=

############
# Functions
############

# bool get_service_index(service, index)
#
#   Print the index of 'service'.  'index' is the current index.
#
get_service_index() {
	if [[ -z $1 || -z $2 ]]; then
		echo "0"
		return 1
	fi
	
	local x myservice="$1" index="$2"

	# Do we already have the index?
	if [[ -n ${index} && ${index} -gt 0 \
		&& ${myservice} == ${RC_DEPEND_TREE[${index}]} ]]; then
			echo "${index}"
			return 0
	fi

	for (( x=1; x<${RC_DEPEND_TREE[0]}; x++ )); do
		index=$(( ${x} * ${rc_index_scale} ))
		if [[ ${myservice} == ${RC_DEPEND_TREE[${index}]} ]]; then
			echo "${index}"
			return 0
		fi
	done

	echo "0"
	return 1
}

# bool get_dep_info(service)
#
#   Set the Dependency variables to contain data for 'service'
#
get_dep_info() {
	[[ -z $1 ]] && return 1
	
	local myservice="$1"

	# We already have the right stuff ...
	[[ ${myservice} == ${rc_name} && -n ${rc_mtime} ]] && return 0

	rc_index="`get_service_index "${myservice}" "${rc_index}"`"
	rc_mtime="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_mtime}))]}"

	# Verify that we have the correct index (rc_index) ...
	# [[ ${rc_index} == "0" ]] && return 1
		
	rc_name="${RC_DEPEND_TREE[${rc_index}]}"
	rc_ineed="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_ineed}))]}"
	rc_needsme="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_needsme}))]}"
	rc_iuse="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_iuse}))]}"
	rc_usesme="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_usesme}))]}"
	rc_ibefore="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_ibefore}))]}"
	rc_iafter="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_iafter}))]}"
	rc_broken="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_broken}))]}"
	rc_parallel="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_parallel}))]}"
	rc_mtime="${RC_DEPEND_TREE[$((${rc_index} + ${rc_type_mtime}))]}"
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
	[[ -z $1 || -z $2 ]] && return 1
	
	local x myservice deps

	# Set the dependency variables to relate to 'service1'
	if [[ $2 == "-t" ]]; then
		[[ -z $3 || -z $4 ]] && return 1
		myservice="$3"
	else
		myservice="$2"
	fi

	if ! get_dep_info "${myservice}" >/dev/null ; then
		eerror "Could not get dependency info for \"${myservice}\"!" > /dev/stderr
		eerror "Please run:" > /dev/stderr
		eerror "  # /sbin/depscan.sh" > /dev/stderr
		eerror "to try and fix this." > /dev/stderr
		return 1
	fi

	# Do we have valid info for 'deptype' ?
	eval deps=\"\$\{rc_$1\}\"
	[[ -z ${deps} ]] && return 1

	if [[ $2 == "-t" && -n $4 ]]; then
		# Check if 'service1' have 'deptype' dependency on 'service2'
		for x in ${deps}; do
			[[ ${x} == $4 ]] && return 0
		done
		return 1
	else
		# Just list all services that 'service1' have 'deptype' dependency on.
		echo "${deps}"
		return 0
	fi
}

# Same as for check_dependency, except 'deptype' is set to
# 'ineed'.  It will return all the services 'service1' NEED's.
ineed() {
	check_dependency ineed "$@" 
}

# Same as for check_dependency, except 'deptype' is set to
# 'needsme'.  It will return all the services that NEED 'service1'.
needsme() {
	check_dependency needsme "$@"
}

# Same as for check_dependency, except 'deptype' is set to
# 'iuse'.  It will return all the services 'service1' USE's.
iuse() {
	check_dependency iuse "$@"
}

# Same as for check_dependency, except 'deptype' is set to
# 'usesme'.  It will return all the services that USE 'service1'.
usesme() {
	check_dependency usesme "$@"
}

# Same as for check_dependency, except 'deptype' is set to
# 'ibefore'.  It will return all the services that are started
# *after* 'service1' (iow, it will start 'service1' before the
# list of services returned).
ibefore() {
	check_dependency ibefore "$@"
}

# Same as for check_dependency, except 'deptype' is set to
# 'iafter'.  It will return all the services that are started
# *before* 'service1' (iow, it will start 'service1' after the
# list of services returned).
iafter() {
	check_dependency iafter "$@"
}

# Same as for check_dependency, except 'deptype' is set to
# 'broken'.  It will return all the services that 'service1'
# NEED, but are not present.
broken() {
	check_dependency broken "$@"
}

# bool iparallel(service)
#
#   Returns true if the service can be started in parallel.
#
iparallel() {
	! check_dependency parallel -t "$1" "no"
}

# bool is_fake_service(service, runlevel)
#
#   Returns ture if 'service' is a fake service in 'runlevel'.
#
is_fake_service() {
	local x fake_services

	[[ -z $1 || -z $2 ]] && return 1

	[[ $2 != ${BOOTLEVEL} && -e "/etc/runlevels/${BOOTLEVEL}/.fake" ]] \
		&& fake_services="$( < /etc/runlevels/${BOOTLEVEL}/.fake )"

	[[ -e "/etc/runlevels/$2/.fake" ]] \
		&& fake_services="${fake_services} $( < /etc/runlevels/$2/.fake )"

	for x in ${fake_services}; do
		[[ $1 == ${x##*/} ]] && return 0
	done

	return 1
}

# bool in_runlevel(service, runlevel)
#
#   Returns true if 'service' is in runlevel 'runlevel'.
#
in_runlevel() {
	[[ -z $1 || -z $2 ]] && return 1

	[[ -L "/etc/runlevels/$2/$1" ]] && return 0

	return 1
}

# bool is_runlevel_start()
#
#   Returns true if it is a runlevel change, and we are busy
#   starting services.
#
is_runlevel_start() {
	[[ -d "${svcdir}/softscripts.old" ]] && return 0

	return 1
}

# bool is_runlevel_stop()
#
#   Returns true if it is a runlevel change, and we are busy
#   stopping services.
#
is_runlevel_stop() {
	[[ -d "${svcdir}/softscripts.new" ]] && return 0

	return 1
}

# int start_service(service)
#
#   Start 'service' if it is not already running.
#
start_service() {
	[[ -z $1 ]] && return 1
	! service_stopped "$1" && return 0

	splash "svc_start" "$1"
	
	if is_fake_service "$1" "${SOFTLEVEL}" ; then
		mark_service_started "$1"
		splash "svc_started" "$1" "0"
		return 0
	fi
	
	(. /sbin/runscript.sh "/etc/init.d/$1" start)
	local retval="$?"
	splash "svc_started" "$1" "${retval}"
	return "${retval}"
}

# int stop_service(service)
#
#   Stop 'service' if it is not already running.
#
stop_service() {
	[[ -z $1 ]] && return 1

	! service_started "$1" && return 0

	splash "svc_stop" "$1"
	
	local level="${SOFTLEVEL}"
	is_runlevel_stop && level="${OLDSOFTLEVEL}"

	if is_fake_service "$1" "${level}" ; then
		mark_service_stopped "$1"
		splash "svc_stopped" "$1" "0"
		return 0
	fi

	(. /sbin/runscript.sh "/etc/init.d/$1" stop)
	local retval="$?"
	splash "svc_stopped" "$1" "${retval}"
	return "${retval}"
}

# bool mark_service_starting(service)
#
#   Mark 'service' as starting.
#
mark_service_starting() {
	[[ -z $1 ]] && return 1

	ln -snf "/etc/init.d/$1" "${svcdir}/starting/$1"
	local retval=$?
	
	[[ -f "${svcdir}/inactive/$1" ]] && rm -f "${svcdir}/inactive/$1"
	
	return "${retval}"
}

# bool mark_service_started(service)
#
#   Mark 'service' as started.
#
mark_service_started() {
	[[ -z $1 ]] && return 1

	ln -snf "/etc/init.d/$1" "${svcdir}/started/$1"
	local retval="$?"
	
	[[ -f "${svcdir}/starting/$1" ]] && rm -f "${svcdir}/starting/$1"
	[[ -f "${svcdir}/inactive/$1" ]] && rm -f "${svcdir}/inactive/$1"
	[[ -f "${svcdir}/stopping/$1" ]] && rm -f "${svcdir}/stopping/$1"

	return "${retval}"
}

# bool mark_service_inactive(service)
#
#   Mark service as inactive
#
mark_service_inactive() {
	[[ -z $1 ]] && return 1

	ln -snf "/etc/init.d/$1" "${svcdir}/inactive/$1"

	return $?
}

# bool mark_service_stopping(service)
#
#   Mark 'service' as stopping.
#
mark_service_stopping() {
	[[ -z $1 ]] && return 1

	ln -snf "/etc/init.d/$1" "${svcdir}/stopping/$1"
	local retval="$?"
	
	[ -f "${svcdir}/starting/$1" ] && rm -f "${svcdir}/starting/$1"
	[ -f "${svcdir}/started/$1" ] && rm -f "${svcdir}/started/$1"
	[ -f "${svcdir}/inactive/$1" ] && rm -f "${svcdir}/inactive/$1"

	return "${retval}"
}

# bool mark_service_stopped(service)
#
#   Mark 'service' as stopped.
#
mark_service_stopped() {
	[[ -z $1 ]] && return 1

	[[ -f "${svcdir}/starting/$1" ]] && rm -f "${svcdir}/starting/$1"
	[[ -f "${svcdir}/started/$1" ]] && rm -f "${svcdir}/started/$1"
	[[ -f "${svcdir}/inactive/$1" ]] && rm -f "${svcdir}/inactive/$1"
	[[ -f "${svcdir}/stopping/$1" ]] && rm -f "${svcdir}/stopping/$1"

	return $?
}

# bool test_service_state(char *service, char *state)
#
#   Returns 0 if the service link exists and points to a file, otherwise 1
#   If 1 then the link is erased if it exists
test_service_state() {
	[[ -z $1 || -z $2 ]] && return 1

	local f="${svcdir}/$2/$1"
	
	[[ -L ${f} ]] || return 1
	
	if [[ ! -e ${f} ]]; then
		rm -f "${f}"
		return 1
	fi
	
	return 0
}

# bool service_starting(service)
#
#   Returns true if 'service' is starting
#
service_starting() {
	test_service_state "$1" "starting"
}

# bool service_started(service)
#
#   Returns true if 'service' is started
#
service_started() {
	test_service_state "$1" "started"
}

# bool service_inactive(service)
#
#   Returns true if 'service' is inactive
#
service_inactive() {
	test_service_state "$1" "inactive"
}

# bool service_stopping(service)
#
#   Returns true if 'service' is stopping
#
service_stopping() {
	test_service_state "$1" "stopping"
}

# bool service_stopped(service)
#
#   Returns true if 'service' is stopped
#
service_stopped() {
	[[ -z $1 ]] && return 1

	service_starting "$1" && return 1
	service_started "$1" && return 1
	service_stopping "$1" && return 1

	return 0
}

# bool mark_service_failed(service)
#
#   Mark service as failed for current runlevel.  Note that
#   this is only valid on runlevel change ...
#
mark_service_failed() {
	[[ -z $1 || ! -d "${svcdir}/failed" ]] && return 1

	ln -snf "/etc/init.d/$1" "${svcdir}/failed/$1"
}

# bool service_failed(service)
#
#   Return true if 'service' have failed during this runlevel.
#
service_failed() {
	[[ -n $1 && -L "${svcdir}/failed/$1" ]]
}

# bool net_service(service)
#
#   Returns true if 'service' is a service controlling a network interface
#
net_service() {
	[[ -n $1 && ${1%%.*} == "net" && ${1##*.} != $1 ]]
}

# bool is_net_up()
#
#    Return true if service 'net' is considered up, else false.
#
#    Notes for RC_NET_STRICT_CHECKING values:
#      none  net is up without checking anything - usefull for vservers
#      lo    Interface 'lo' is counted and if only it is up, net is up.
#      no    Interface 'lo' is not counted, and net is down even with it up,
#            so there have to be at least one other interface up.
#      yes   All interfaces must be up.
is_net_up() {
	local netcount=0

	case "${RC_NET_STRICT_CHECKING}" in
		none)
			return 0
			;;
		lo)
			netcount="$(ls -1 "${svcdir}"/started/net.* 2> /dev/null | \
			            egrep -c "\/net\..*$")"
			;;
		*)
			netcount="$(ls -1 "${svcdir}"/started/net.* 2> /dev/null | \
			            grep -v 'net\.lo' | egrep -c "\/net\..*$")"
			;;
	esac

	# Only worry about net.* services if this is the last one running,
	# or if RC_NET_STRICT_CHECKING is set ...
	if [ "${netcount}" -lt 1 -o "${RC_NET_STRICT_CHECKING}" = "yes" ]
	then
		return 1
	fi

	return 0
}

# void schedule_service_startup(service)
#
#   Schedule 'service' for startup, in parallel if possible.
#
schedule_service_startup() {
	if [[ ${RC_PARALLEL_STARTUP} != "yes" ]]; then
		start_service "$1"
		return 0
	fi

	local current_job= count="$( jobs | grep -c "Running" )"

	set -m +b

	if [[ ${count} -gt 0 ]]; then
		# Wait until we have only one service running
		while [[ ${count} -gt 1 ]]; do
			count="$( jobs | grep -c "Running" )"
		done

		current_job="$(jobs | awk '/Running/ { print $4}')"

		# Wait if we cannot start this service with the already running
		# one (running one might start this one ...).
		query_before "$1" "${current_job}" && wait
	fi

	if iparallel "$1"
	then
		eval start_service "$1" \&
	else
		# Do not start with any service running if we cannot start
		# this service in parallel ...
#		wait
		
		start_service "$1"
	fi

	return 0
}

# bool dependon(service1, service2)
#
#   Does service1 depend (NEED or USE) on service2 ?
#
dependon() {
	ineed -t "$1" "$2" || iuse -t "$1" "$2"
}

# string validi(use/after, service)
#
#   This is the main code for valid_after and valid_iuse
#   No point in writing it twice!
valid_i() {
	[[ $1 != "after" && $1 != "use" ]] && return 1

	local x mylevel=$( < "${svcdir}/softlevel" )
	# Cannot be SOFTLEVEL, as we need to know current runlevel

	for x in $( i$1 "$2" )
	do
		[[ -e "/etc/runlevels/${BOOTLEVEL}/${x}" \
			|| -e "/etc/runlevels/${mylevel}/${x}" \
			|| ${x} == "net" ]] \
				&& echo "${x}"
	done

	return 0
}

# string valid_iuse(service)
#
#   This will only give the valid use's for the service
#   (they must be in the boot or current runlevel)
#
valid_iuse() {
	valid_i "use" "$1"
}

#string valid_iafter(service)
#
#   Valid services for current or boot rc level that should start
#   before 'service'
#
valid_iafter() {
	valid_i "after" "$1"
}

# string trace_dependencies(service[s])
#
#   Get and sort the dependencies of given service[s].
#
trace_dependencies() {
	local -a unsorted=( "$@" )
	local -a sorted dependencies
	local service dependency x deptype

	case "$1" in
		-*)
			deptype=${1/-}
			unsorted=( "${myservice}" )
			;;
	esac
	
	while (( ${#unsorted[*]} > 0 )) ; do
		# Get a service from the list and remove it
		service=${unsorted[0]}
		unset unsorted[0]
		# Reindex the array
		unsorted=( ${unsorted[@]} )
	
		if [[ -n ${deptype} ]] ; then
			dependencies=( $( "${deptype}" "${service}" ) )
		else
			# Services that should start before $service
			dependencies=( $(ineed "${service}") $(valid_iuse "service") )
			if is_runlevel_start || is_runlevel_stop ; then
				dependencies=( "${dependencies[@]}" $(valid_iafter "${service}") )
			fi
		fi
	
		# Remove each one of those from the sorted list and add
		# them all to the unsorted so we analyze them later
		for dependency in ${dependencies[@]} ; do
			for (( x=0 ; x < ${#sorted[*]} ; x++ )) ; do
				[[ ${sorted[x]} == "${dependency}" ]] && \
					unset sorted[x]
			done
			for (( x=0 ; x < ${#unsorted[*]} ; x++ )) ; do
				[[ ${unsorted[x]} == "${dependency}" ]] && \
					unset unsorted[x]
			done
			
			sorted=( ${sorted[@]} )
			unsorted=( ${unsorted[@]} ${dependency} )
		done
	
		sorted=( ${service} ${sorted[@]} )
	done

	# If deptype is set, we do not want the name of this service
	if [[ -n ${deptype} ]] ; then
		for (( x=0 ; x < ${#sorted[*]} ; x++ )) ; do
			[[ ${sorted[x]} == "${myservice}" ]] && \
				unset sorted[x]
		done
		sorted=( ${sorted[@]} )
	fi
	
	echo ${sorted[@]}
}

# bool query_before(service1, service2)
#
#   Return true if 'service2' should be started *before*
#   service1.
#
query_before() {
	local x list
	local netservice="no"

	[[ -z $1 || -z $2 ]] && return 1

	list=$( trace_dependencies "$1" )

	net_service "$2" && netservice="yes"
	
	for x in ${list} ; do
		[[ ${x} == "$2" ]] && return 0

		# Also match "net" if this is a network service ...
		[[ ${netservice} == "yes" && ${x} == "net" ]] && return 0
	done

	return 1
}

# vim:ts=4
