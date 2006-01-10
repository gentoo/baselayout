# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# RC Dependency and misc service functions

RC_GOT_SERVICES="yes"

[[ ${RC_GOT_FUNCTIONS} != "yes" ]] && source /sbin/functions.sh

if [[ ${RC_GOT_DEPTREE_INFO} != "yes" ]] ; then
	# Only try and update if we are root
	if [[ ${EUID} == "0" ]] && ! /sbin/depscan.sh -u ; then
		echo
		eerror "Error running '/sbin/depscan.sh'!"
		eerror "Please correct any problems above."
		exit 1
	fi

	source "${svcdir}/deptree"
	if [[ ${RC_GOT_DEPTREE_INFO} != "yes" ]] ; then
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
rc_mtime=

############
# Functions
############

# bool get_service_index(service, index)
#
#   Print the index of 'service'.  'index' is the current index.
#
get_service_index() {
	if [[ -z $1 || -z $2 ]] ; then
		echo "0"
		return 1
	fi
	
	local x myservice="$1" index="$2"

	# Do we already have the index?
	if [[ -n ${index} && ${index} -gt 0 \
		&& ${myservice} == "${RC_DEPEND_TREE[${index}]}" ]] ; then
			echo "${index}"
			return 0
	fi

	for (( x=1; x<=${RC_DEPEND_TREE[0]}; x++ )); do
		index=$(( ${x} * ${rc_index_scale} ))
		if [[ ${myservice} == "${RC_DEPEND_TREE[${index}]}" ]] ; then
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
	[[ ${myservice} == "${rc_name}" && -n ${rc_mtime} ]] && return 0

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
	if [[ $2 == "-t" ]] ; then
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
		for x in ${deps} ; do
			[[ ${x} == "$4" ]] && return 0
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

# bool is_fake_service(service, runlevel)
#
#   Returns ture if 'service' is a fake service in 'runlevel'.
#
is_fake_service() {
	local x fake_services

	[[ -z $1 || -z $2 ]] && return 1

	[[ $2 != "${BOOTLEVEL}" && -e /etc/runlevels/"${BOOTLEVEL}"/.fake ]] && \
		fake_services=$( < /etc/runlevels/"${BOOTLEVEL}"/.fake )

	[[ -e /etc/runlevels/"$2"/.fake ]] && \
		fake_services="${fake_services} $( < /etc/runlevels/$2/.fake )"

	for x in ${fake_services} ; do
		[[ $1 == "${x##*/}" ]] && return 0
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
	[[ -d "${svcdir}/softscripts.old" ]]
}

# bool is_runlevel_stop()
#
#   Returns true if it is a runlevel change, and we are busy
#   stopping services.
#
is_runlevel_stop() {
	[[ -d "${svcdir}/softscripts.new" ]]
}

# void sevice_message([char *type] char *message)
#
# Print out a service message if we are on parallel
service_message() {
	[[ ${RC_PARALLEL_STARTUP} != "yes" ]] && return

	local cmd="einfo"
	if [[ $1 == "1" || $1 == "error" || $1 == "eerror" ]] ; then
		cmd="eerror"
		shift
	fi

	local r="${RC_QUIET_STDOUT}"
	RC_QUIET_STDOUT="no"
	${cmd} "$@"
	RC_QUIET_STDOUT=${r}
}

# bool begin_service( service )
#
#   atomically marks the service as being executed
#   use like this:
#
#   if begin_service service ; then
#         whatever is in here can only be executed by one process
#         end_service service
#   fi
begin_service() {
	local service="$1"
	[[ -z ${service} ]] && return 1
	
	[[ ${START_CRITICAL} == "yes" ]] && return 0

	mkfifo "${svcdir}/exclusive/${service}" 2> /dev/null
}

# void end_service(service, exitcode)
#
#   stops executing a exclusive region and
#   wakes up anybody who is waiting for the exclusive region
#
end_service() {
	local service="$1" exitstatus="$2"
	[[ -z ${service} ]] && return

	# if we are doing critical services, there is no fifo
	[[ ${START_CRITICAL} == "yes" ]] && return

	if [[ -n ${exitstatus} ]] ; then
		echo "${exitstatus}" > "${svcdir}/exitcodes/${service}"
	fi

	# move the fifo to a unique name so no-one is waiting for it
	local fifo="${svcdir}/exclusive/${service}"
	if [[ -e ${fifo} ]] ; then
		local tempname="${fifo}.$$"
		mv -f "${fifo}" "${tempname}"

		# wake up anybody that was waiting for the fifo
		touch "${tempname}"

		# We dont need the fifo anymore
		rm -f "${tempname}"
	fi
}

# int wait_service(service)
#
# If a service has started, or a fifo does not exist return 0
# Otherwise, wait until we get an exit code via the fifo and return
# that instead.
wait_service() {
	local service="$1"
	local fifo="${svcdir}/exclusive/${service}"
	
	[[ ${START_CRITICAL} == "yes" || ${STOP_CRITICAL} == "yes" ]] && return 0
	[[ ! -e ${fifo} ]] && return 0

	# This will block until the service fifo is touched
	# Otheriwse we don't block
	local tmp=$( < "${fifo}" &>/dev/null )
	local exitstatus=$( < "${svcdir}/exitcodes/${service}" )

	return "${exitstatus}"
}

# int start_service(service)
#
#   Start 'service' if it is not already running.
#
start_service() {
	local service="$1"
	[[ -z ${service} ]] && return 1

	if [[ ! -e "/etc/init.d/${service}" ]] ; then
		mark_service_stopped "${service}"
		return 1
	fi

	service_starting "${service}" && return 0
	service_started "${service}" && return 0
	service_inactive "${service}" && return 1

	if is_fake_service "${service}" "${SOFTLEVEL}" ; then
		mark_service_started "${service}"
		splash "svc_start" "${service}"
		splash "svc_started" "${service}" "0"
		return 0
	fi

	begin_service "${service}" || return 0
	splash "svc_start" "${service}"
	if [[ ${RC_PARALLEL_STARTUP} != "yes" || \
		  ${START_CRITICAL} == "yes" ]] ; then
		# if we can not start the services in parallel
		# then just start it and return the exit status
		( "/etc/init.d/${service}" start )
		retval=$?
		splash "svc_started" "${service}" "${retval}"
		end_service "${service}" "${retval}"
		return "${retval}"
	else
		# if parallel startup is allowed, start it in background
		(
			"/etc/init.d/${service}" start 
			retval=$?
			splash "svc_started" "${service}" "${retval}"
			end_service "${service}" "${retval}"
		) &
		return 0
	fi
}

# int stop_service(service)
#
#   Stop 'service' if it is not already running.
#
stop_service() {
	local service="$1"
	[[ -z ${service} ]] && return 1

	if [[ ! -e "/etc/init.d/${service}" ]] ; then
		mark_service_stopped "${service}"
		return 0
	fi

	service_stopping "${service}" && return 0
	service_stopped "${service}" && return 0
	
	local level="${SOFTLEVEL}"
	is_runlevel_stop && level="${OLDSOFTLEVEL}"

	if is_fake_service "${service}" "${level}" ; then
		splash "svc_stop" "${service}"
		mark_service_stopped "${service}"
		splash "svc_stopped" "${service}" "0"
		return 0
	fi

	begin_service "${service}" || return 0

	splash "svc_stop" "${service}"
	if [[ ${RC_PARALLEL_STARTUP} != "yes" || \
		  ${STOP_CRITICAL} == "yes" ]] ; then
		# if we can not start the services in parallel
		# then just start it and return the exit status
		( "/etc/init.d/${service}" stop )
		retval=$?
		splash "svc_stopped" "${service}" "${retval}"
		end_service "${service}" "${retval}"
		return "${retval}"
	else
		# if parallel startup is allowed, start it in background
		(
			( "/etc/init.d/${service}" stop )
			retval=$?
			splash "svc_stopped" "${service}" "${retval}"
			end_service "${service}" "${retval}"
		) &
		return 0
	fi
}

# bool mark_service_starting(service)
#
#   Mark 'service' as starting.
#
mark_service_starting() {
	[[ -z $1 ]] && return 1

	ln -sn "/etc/init.d/$1" "${svcdir}/starting/$1" 2>/dev/null || return 1

	[[ -f "${svcdir}/inactive/$1" ]] && rm -f "${svcdir}/inactive/$1"
	[[ -f "${svcdir}/started/$1" ]] && rm -f "${svcdir}/started/$1"
	return 0
}

# bool mark_service_started(service)
#
#   Mark 'service' as started.
#
mark_service_started() {
	[[ -z $1 ]] && return 1

	ln -snf "/etc/init.d/$1" "${svcdir}/started/$1"
	
	[[ -f "${svcdir}/starting/$1" ]] && rm -f "${svcdir}/starting/$1"
	[[ -f "${svcdir}/inactive/$1" ]] && rm -f "${svcdir}/inactive/$1"
	[[ -f "${svcdir}/stopping/$1" ]] && rm -f "${svcdir}/stopping/$1"

	return 0 
}

# bool mark_service_inactive(service)
#
#   Mark service as inactive
#
mark_service_inactive() {
	[[ -z $1 ]] && return 1

	ln -snf "/etc/init.d/$1" "${svcdir}/inactive/$1"
	
	[[ -f "${svcdir}/started/$1" ]] && rm -f "${svcdir}/started/$1"
	[[ -f "${svcdir}/starting/$1" ]] && rm -f "${svcdir}/starting/$1"
	[[ -f "${svcdir}/stopping/$1" ]] && rm -f "${svcdir}/stopping/$1"

	return 0
}

# bool mark_service_stopping(service)
#
#   Mark 'service' as stopping.
#
mark_service_stopping() {
	[[ -z $1 ]] && return 1

	ln -sn "/etc/init.d/$1" "${svcdir}/stopping/$1" 2>/dev/null || return 1

	[[ -f "${svcdir}/inactive/$1" ]] && rm -f "${svcdir}/inactive/$1"
	[[ -f "${svcdir}/started/$1" ]] && rm -f "${svcdir}/started/$1"
	return 0
}

# bool mark_service_stopped(service)
#
#   Mark 'service' as stopped.
#
mark_service_stopped() {
	[[ -z $1 ]] && return 1

	[[ -f "${svcdir}/daemons/$1" ]] && rm -f "${svcdir}/daemons/$1"
	[[ -f "${svcdir}/starting/$1" ]] && rm -f "${svcdir}/starting/$1"
	[[ -f "${svcdir}/started/$1" ]] && rm -f "${svcdir}/started/$1"
	[[ -f "${svcdir}/inactive/$1" ]] && rm -f "${svcdir}/inactive/$1"
	[[ -f "${svcdir}/stopping/$1" ]] && rm -f "${svcdir}/stopping/$1"

	return 0
}

# bool test_service_state(char *service, char *state)
#
#   Returns 0 if the service link exists and points to a file, otherwise 1
#   If 1 then the link is erased if it exists
test_service_state() {
	[[ -z $1 || -z $2 ]] && return 1

	local f="${svcdir}/$2/$1"
	
	# Service is in the state requested
	[[ -L ${f} ]] && return 0
	
	[[ ! -e ${f} ]] && rm -f "${f}"
	return 1
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
	service_inactive "$1" && return 1

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

# bool service_started_daemon(char *interface, char *daemon, int index)
# Returns 0 if the service started the given daemon
# via start-stop-daemon, otherwise 1.
# If index is emtpy, then we don't care what the first daemon launched
# was, otherwise the daemon must also be at that index
service_started_daemon() {
	local service="$1" daemon="$2" index="${3:-[0-9]*}"
	local daemonfile="${svcdir}/daemons/${service}"

	[[ ! -e ${daemonfile} ]] && return 1
	grep -q '^RC_DAEMONS\['"${index}"'\]="'${daemon}'"$' "${daemonfile}"
}

# bool net_service(service)
#
#   Returns true if 'service' is a service controlling a network interface
#
net_service() {
	[[ -n $1 && ${1%%.*} == "net" && ${1##*.} != "$1" ]]
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
	if [[ "${netcount}" -lt 1 || ${RC_NET_STRICT_CHECKING} == "yes" ]] ; then
		return 1
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
	local x
	# Just set to dummy for now (don't know if $svcdir/softlevel exists yet).
	local mylevel="${BOOTLEVEL}"

	[[ $1 != "after" && $1 != "use" ]] && return 1

	# Cannot be SOFTLEVEL, as we need to know current runlevel
	[[ -f "${svcdir}/softlevel" ]] && mylevel=$( < "${svcdir}/softlevel" )

	for x in $( i$1 "$2" ) ; do
		[[ -e "/etc/runlevels/${BOOTLEVEL}/${x}" || \
		   -e "/etc/runlevels/${mylevel}/${x}" || \
		   ${x} == "net" ]] \
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
	local -a services=( "$@" ) net_deps
	local i j net_services x

	if [[ $1 == -* ]]; then
		deptype="${1/-/}"
		if net_service "${myservice}" ; then
			services=( "net" "${myservice}" )
		else
			services=( "${myservice}" )
		fi
	fi

	net_services=$( cd "${svcdir}"/started; ls net.* 2>/dev/null )
	# If no net services are running or we only have net.lo up, then
	# assume we are in boot runlevel or starting a new runlevel
	if [[ -z ${net_services} || ${net_services} == "net.lo" ]]; then
		get_net_services() {
			local runlevel="$1"

			if [[ -d "/etc/runlevels/${runlevel}" ]] ; then
				cd "/etc/runlevels/${runlevel}"
				ls net.* 2>/dev/null
			fi
		}

		local mylevel="${BOOTLEVEL}"
		local x=$( get_net_services "${mylevel}" )

		[[ -f "${svcdir}/softlevel" ]] && mylevel=$( < "${svcdir}/softlevel" )
		[[ ${BOOTLEVEL} != "${mylevel}" ]] && \
			local x="${x} $( get_net_services "${mylevel}" )"
		[[ -n ${x} ]] && net_services="${x}"
	fi

	# Cache the generic "net" depends
	net_deps=( $( ineed net ) $( valid_iuse net )	)
	if is_runlevel_start || is_runlevel_stop ; then
		net_deps=( "${net_deps[@]}" $( valid_iafter net ) )
	fi

	# OK, this is a topological sort
	# The bonus about doing it in bash is that we can calculate our sort
	# order as we calculate our dependencies
	local -a visited sorted
	visit_service() {
		local service="$1" dep x
		local -a deps

		[[ " ${visited[@]} " == *" ${service} "* ]] && return
		visited=( "${visited[@]}" "${service}" )

		if [[ -n ${deptype} ]] ; then
			deps=( $( "${deptype}" "${service}" ) )
		else
			deps=( $( ineed "${service}" ) $( valid_iuse "${service}" ) ) 
			if is_runlevel_start || is_runlevel_stop ; then
				deps=( "${deps[@]}" $( valid_iafter "${service}" ) )
			fi

			# If we're a net service, we have to get deps for ourself
			# and the net service as we're both
			net_service "${service}" && deps=( "${deps[@]}" "${net_deps[@]}" )
			
			x=" ${deps[@]} "
			deps=( "${deps[@]}" ${x// net / ${net_services} } )
		fi

		services=( "${services[@]}" "${deps[@]}" )
		for dep in ${deps[@]}; do
			visit_service "${dep}"
		done
		sorted=( "${sorted[@]}" "${service}" )
	}
		
	for (( i=0; i<${#services[@]}; i++)); do
		visit_service "${services[i]}"
	done

	services=( "${sorted[@]}" )

	if [[ -n ${deptype} ]] ; then
		# If deptype is set, we do not want the name of this service
		x=" ${services[@]} "
		services=( ${x// ${myservice} / } )

		# If its a net service, do not include "net"
		if net_service "${myservice}" ; then
			x=" ${services[@]} "
			sorted=( ${services// net / } )
		fi
	fi

	echo "${services[@]}"
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
