# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# RC Dependency and misc service functions
if [[ ${RC_GOT_SERVICES} != "yes" ]] ; then
	RC_GOT_SERVICES="yes"
	[[ ${EUID} == "0" && $0 != "/etc/init.d/halt.sh" ]] && depscan.sh
fi

[[ ${RC_GOT_FUNCTIONS} != "yes" ]] && source /sbin/functions.sh

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

# void save_options(char *option, char *optstring)
#
#    save the settings ("optstring") for "option"
#
save_options() {
	local myopts="$1"

	shift
	if [[ ! -d "${svcdir}/options/${SVCNAME}" ]] ; then
		mkdir -p -m 0755 "${svcdir}/options/${SVCNAME}"
	fi

	echo "$*" > "${svcdir}/options/${SVCNAME}/${myopts}"
}

# char *get_options(char *option)
#
#    get the "optstring" for "option" that was saved
#    by calling the save_options function
#
get_options() {
	local svc="${SVCNAME}"
	[[ -n $2 ]] && svc="$2"
	
	if [[ -f "${svcdir}/options/${svc}/$1" ]] ; then
		echo "$(< ${svcdir}/options/${svc}/$1)"
	fi
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
	
	mkfifo "${svcdir}/exclusive/${service}" 2> /dev/null
}

# void end_service(service)
#
#   stops executing a exclusive region and
#   wakes up anybody who is waiting for the exclusive region
#
end_service() {
	local service="$1"
	[[ -z ${service} ]] && return

	# move the fifo to a unique name so no-one is waiting for it
	local fifo="${svcdir}/exclusive/${service}"
	if [[ -e ${fifo} ]] ; then
		local tempname="${fifo}.$$"
		mv -f "${fifo}" "${tempname}"
		# wake up anybody that was waiting for the fifo
		# Linux requires using touch, otherwise things go wrong
		touch "${tempname}"
		# We dont need the fifo anymore
		rm -f "${tempname}"
	fi
}

# void wait_service(service)
#
# Wait until the given service has finished
wait_service() {
	local service="$1"
	local fifo="${svcdir}/exclusive/${service}"
	
	[[ ! -e ${fifo} ]] && return

	# This will block until the service fifo is touched
	# Otheriwse we don't block
	# FreeBSD has numerous FIFO issues, so wait in a loop
	# http://www.freebsd.org/cgi/query-pr.cgi?pr=kern/94772
	if [[ $(uname) == "FreeBSD" ]] ; then
		while [[ -e ${fifo} ]] ; do
			sleep 1 
		done
		sync # Things don't work unless we sync
	else
		# Use cat as bash internals always throw errors to console
		cat "${fifo}" &>/dev/null
	fi
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

	begin_service "${service}" || return 0
	splash "svc_start" "${service}"

	if [[ ${RC_PARALLEL_STARTUP} != "yes" ]] ; then
		# if we can not start the services in parallel
		# then just start it and return the exit status
		(
			profiling name "/etc/init.d/${service} start"
			"/etc/init.d/${service}" start
		)
		
		service_started "${service}" || service_inactive "${service}" \
			|| service_scheduled "${service}"
		retval=$?
		
		end_service "${service}"
		splash "svc_started" "${service}" "${retval}"
		
		return "${retval}"
	else
		# if parallel startup is allowed, start it in background
		(
			profiling name "/etc/init.d/${service} start"
			"/etc/init.d/${service}" start
			
			service_started "${service}" || service_inactive "${service}" \
				|| service_scheduled "${service}"
			retval=$?
			
			end_service "${service}"
			splash "svc_started" "${service}" "${retval}"
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

	begin_service "${service}" || return 0

	splash "svc_stop" "${service}"
	if [[ ${RC_PARALLEL_STARTUP} != "yes" ]] ; then
		# if we can not start the services in parallel
		# then just start it and return the exit status
		( "/etc/init.d/${service}" stop )
		service_stopped "${service}"
		retval=$?
		end_service "${service}"
		splash "svc_stopped" "${service}" "${retval}"
		return "${retval}"
	else
		# if parallel startup is allowed, start it in background
		(
			( "/etc/init.d/${service}" stop )
			service_stopped "${service}"
			retval=$?
			end_service "${service}"
			splash "svc_stopped" "${service}" "${retval}"
		) &
		return 0
	fi
}

# bool mark_service_coldplugged(service)
#
#   Mark 'service' as coldplugged.
#
mark_service_coldplugged() {
	[[ -z $1 ]] && return 1

	ln -snf "/etc/init.d/$1" "${svcdir}/coldplugged/$1"
	return 0
}

# bool mark_service_starting(service)
#
#   Mark 'service' as starting.
#
mark_service_starting() {
	[[ -z $1 ]] && return 1

	ln -sn "/etc/init.d/$1" "${svcdir}/starting/$1" 2>/dev/null || return 1

	[[ -f "${svcdir}/started/$1" ]] && rm -f "${svcdir}/started/$1"
	[[ -f "${svcdir}/inactive/$1" ]] \
		&& mv "${svcdir}/inactive/$1" "${svcdir}/wasinactive/$1"
	return 0
}

# bool mark_service_started(service)
#
#   Mark 'service' as started.
#
mark_service_started() {
	[[ -z $1 ]] && return 1

	ln -snf "/etc/init.d/$1" "${svcdir}/started/$1"
	
	rm -f "${svcdir}/starting/$1" "${svcdir}/inactive/$1" \
		"${svcdir}/wasinactive/$1" "${svcdir}/stopping/$1" \
		"${svcdir}"/scheduled/*/"$1"

	return 0 
}

# bool mark_service_inactive(service)
#
#   Mark service as inactive
#
mark_service_inactive() {
	[[ -z $1 ]] && return 1

	ln -snf "/etc/init.d/$1" "${svcdir}/inactive/$1"
	
	rm -f "${svcdir}/started/$1" "${svcdir}/wasinactive/$1" \
		"${svcdir}/starting/$1" "${svcdir}/stopping/$1"
	
	end_service "$1"

	return 0
}

# bool mark_service_stopping(service)
#
#   Mark 'service' as stopping.
#
mark_service_stopping() {
	[[ -z $1 ]] && return 1

	ln -sn "/etc/init.d/$1" "${svcdir}/stopping/$1" 2>/dev/null || return 1

	rm -f "${svcdir}/started/$1"
	[[ -f "${svcdir}/inactive/$1" ]] \
		&& mv "${svcdir}/inactive/$1" "${svcdir}/wasinactive/$1"
		
	return 0
}

# bool mark_service_stopped(service)
#
#   Mark 'service' as stopped.
#
mark_service_stopped() {
	[[ -z $1 ]] && return 1

	rm -Rf "${svcdir}/daemons/$1" "${svcdir}/starting/$1" \
		"${svcdir}/started/$1" "${svcdir}/inactive/$1" \
		"${svcdir}/wasinactive/$1" "${svcdir}/stopping/$1" \
		"${svcdir}/scheduled/$1" "${svcdir}/options/$1"

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

# bool service_coldplugged(service)
#
#   Returns true if 'service' is coldplugged
#
service_coldplugged() {
	test_service_state "$1" "coldplugged"
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

# bool service_wasinactive(service)
#
#   Returns true if 'service' is inactive
#
service_wasinactive() {
	test_service_state "$1" "wasinactive"
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

# char service_scheduled_by(service)
#
#   Returns a list of services which will try and start 'service' when they
#   are started
#
service_scheduled_by() {
	[[ -z $1 ]] && return 1

	local x= s= r=
	for x in $(dolisting "${svcdir}/scheduled/*/$1") ; do
		s="${x%/*}"
		r="${r} ${s##*/}"
	done

	echo "${r:1}"
}

# bool service_scheduled()
#
#   Returns true if 'service' is scheduled to be started by another service
#
service_scheduled() {
	[[ -n $(service_scheduled_by "$@") ]]
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
	local service="$1" daemon="'$2'" index="${3:-[0-9]*}"
	local daemonfile="${svcdir}/daemons/${service}"

	[[ ! -e ${daemonfile} ]] && return 1
	[[ $'\n'$(<"${daemonfile}")$'\n' \
		=~ $'\n'RC_DAEMONS\[${index}\]=${daemon}$'\n' ]]
}

# bool do_unmount(char *cmd, char *no_unmounts, char *nodes, char *fslist)
# Handy function to handle all our unmounting needs
# get_mounts is our portable function to get mount information
do_unmount() {
	local cmd="$1" no_unmounts="$2" nodes="$3" fslist="$4" retval=0 retry=
	local l= fs= node= point= foo= fuser_opts="-m -c" fuser_kill="-s "
	local pids= pid=
	if [[ $(uname) == "Linux" ]] ; then
		fuser_opts="-c"
		fuser_kill="-"
	fi

	get_mounts | sort -ur -k1,1 | while read point node fs foo ; do
		point=${point//\040/ }
		node=${node//\040/ }
		fs=${fs//\040/ }
		[[ -n ${no_unmounts} && ${point} =~ ${no_unmounts} ]] && continue
		[[ -n ${nodes} && ! ${node} =~ ${nodes} ]] && continue
		[[ -n ${fslist} && ! ${fs} =~ ${fslist} ]] && continue

		if [[ ${cmd} == "umount"* ]] ; then
			# If we're using the mount (probably /usr) then don't unmount us
			if [[ " $(fuser ${fuser_opts} "${point}" 2>/dev/null) " == *" $$ "* ]] ; then
				ewend 1 $"We are using" "${point}," $"not unmounting"
				continue
			fi
		fi

		if [[ ${cmd} == "umount"* ]] ; then
			ebegin $"Unmounting" "${point}"
		else
			ebegin $"Remounting" "${point}"
		fi

		declare -a siglist=( "TERM" "KILL" "KILL" )
		retry=0
		while ! ${cmd} "${point}" &>/dev/null ; do
			# Don't kill if it's us (/ and possibly /usr)
			if [[ " $(fuser ${fuser_opts} "${point}" 2>/dev/null) " != *" $$ "* ]] ; then
				fuser "${fuser_kill}${siglist[${retry}]}" -k ${fuser_opts} \
					"${point}" &>/dev/null
				sleep 2
			else
				# No point in trying again, save time
				retry=3
			fi
			((retry++))

			# OK, try forcing things
			if [[ ${retry} -ge 2 ]] ; then
				${cmd} -f "${point}" || retry=999
				break
			fi
		done
		if [[ ${retry} == 999 ]] ; then
			eend 1
			retval=1
		else
			eend 0
		fi
	done
	return ${retval}
}

# vim: set ts=4 :
