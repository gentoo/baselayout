#!/bin/bash
# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

if [[ $1 == "/"* ]] ; then
	myscript="$1"
else
	myscript="$(pwd)/$1"
fi
cd /

# Common functions
[[ ${RC_GOT_FUNCTIONS} != "yes" ]] && source /sbin/functions.sh

# Sleep until svcdir is unlocked
while [[ -e ${svcdir}/.locked ]] ; do
	ewarn "Sleeping while svcdir is locked"
	sleep 1
done

# Change dir to $svcdir so we lock it for fuser until we finish
cd "${svcdir}"

# User must be root to run most script stuff (except status)
if [[ ${EUID} != "0" ]] && ! [[ $2 == "status" && $# -eq 2 ]] ; then
	eerror "$0: must be root to run init scripts"
	exit 1
fi

if [[ -L $1 && ! -L "/etc/init.d/${1##*/}" ]] ; then
	SVCNAME=$(readlink "$1")
else
	SVCNAME="$1"
fi
declare -r SVCNAME="${SVCNAME##*/}"
export SVCNAME
# Support deprecated myservice variable
myservice="${SVCNAME}"

svc_trap() {
	trap 'eerror "ERROR:  ${SVCNAME} caught an interrupt"; eflush; exit 1' \
		INT QUIT TSTP
}

# Setup a default trap
svc_trap

# Now check script for syntax errors
rcscript_errors=$(bash -n "${myscript}" 2>&1) || {
	[[ -n ${rcscript_errors} ]] && echo "${rcscript_errors}" >&2
	eerror "ERROR:  $1 has syntax errors in it; aborting ..."
	exit 1
}

# coldplug events can trigger init scripts, but we don't want to run them
# until after rc sysinit has completed so we punt them to the boot runlevel
if [[ -e /dev/.rcsysinit ]] ; then
	eerror "ERROR:  cannot run ${SVCNAME} until sysinit completes"
	[[ ${RC_COLDPLUG:-yes} != "yes" ]] && exit 1
	set -f
	for x in ${RC_PLUG_SERVICES} ; do
		[[ ${SVCNAME} == ${x} ]] && break
		[[ "!${SVCNAME}" == ${x} ]] && exit 1
	done
	eerror "${SVCNAME} will be started in the ${BOOTLEVEL} runlevel"
	if [[ ! -L /dev/.rcboot/"${SVCNAME}" ]] ; then
		[[ ! -d /dev/.rcboot ]] && mkdir /dev/.rcboot
		ln -snf "$1" /dev/.rcboot/"${SVCNAME}"
	fi
	exit 1
fi

# Only hotplug if we're allowed to
if [[ ${IN_HOTPLUG} == "1" ]] ; then
	if [[ ${RC_HOTPLUG:-yes} != "yes" ]] ; then
		eerror "${SVCNAME} is not allowed to be hotplugged"
		exit 1
	fi
	
	set -f
	for x in ${RC_PLUG_SERVICES} ; do
		[[ ${SVCNAME} == ${x} ]] && break
		if [[ "!${SVCNAME}" == ${x} ]] ; then
			eerror "${SVCNAME} is not allowed to be hotplugged"
			exit 1
		fi
	done
	set +f
fi


# State variables
svcpause="no"
svcrestart="no"

# Functions to handle dependencies and services
[[ ${RC_GOT_SERVICES} != "yes" ]] && source "${svclib}/sh/rc-services.sh"
# Functions to control daemons
[[ ${RC_GOT_DAEMON} != "yes" ]] && source "${svclib}/sh/rc-daemon.sh"

# Check if the textdomain is non-default
search_lang="${LC_ALL:-${LC_MESSAGES:-${LANG}}}"
[[ -f ${TEXTDOMAINDIR}/${search_lang%.*}/LC_MESSAGES/${myservice}.mo ]] \
	&& TEXTDOMAIN="${myservice}"

# Source configuration files.
# (1) Source /etc/conf.d/net if it is a net.* service
# (2) Source /etc/conf.d/${SVCNAME} to get initscript-specific
#     configuration (if it exists).
# (3) Source /etc/rc.conf to pick up potentially overriding
#     configuration, if the system administrator chose to put it
#     there (if it exists).
if net_service "${SVCNAME}" ; then
	conf=$(add_suffix /etc/conf.d/net)
	[[ -e ${conf} ]] && source "${conf}"
fi
conf=$(add_suffix "/etc/conf.d/${SVCNAME}")
[[ -e ${conf} ]] && source "${conf}"
conf=$(add_suffix /etc/rc.conf)
[[ -e ${conf} ]] && source "${conf}"

mylevel="${SOFTLEVEL}"
[[ ${SOFTLEVEL} == "${BOOTLEVEL}" \
	|| ${SOFTLEVEL} == "reboot" || ${SOFTLEVEL} == "shutdown" ]] \
	&& mylevel="${DEFAULTLEVEL}"

# Call svc_quit if we abort AND we have obtained a lock
service_started "${SVCNAME}"
svcstarted="$?"
service_inactive "${SVCNAME}"
svcinactive="$?"
svc_quit() {
	eerror "ERROR:  ${SVCNAME} caught an interrupt"
	eflush
	if service_inactive "${SVCNAME}" || [[ ${svcinactive} == "0" ]] ; then
		mark_service_inactive "${SVCNAME}"
	elif [[ ${svcstarted} == "0" ]] ; then
		mark_service_started "${SVCNAME}"
	else
		mark_service_stopped "${SVCNAME}"
	fi
	exit 1
}

usage() {
	local IFS="|"
	myline="Usage: ${SVCNAME} { $* "
	echo
	eerror "${myline}}"
	eerror "       ${SVCNAME} without arguments for full help"
}

stop() {
	# Return success so the symlink gets removed
	return 0
}

start() {
	eerror "ERROR:  ${SVCNAME} does not have a start function."
	# Return failure so the symlink doesn't get created
	return 1
}

restart() {
	svc_restart
}

status() {
	# Dummy function
	return 0
}

svc_schedule_start() {
	local service="$1" start="$2"
	[[ ! -d "${svcdir}/scheduled/${service}" ]] \
		&& mkdir -p "${svcdir}/scheduled/${service}"
	ln -snf "/etc/init.d/${service}" \
		"${svcdir}/scheduled/${service}/${start}"
}

svc_start_scheduled() {
	[[ ! -d "${svcdir}/scheduled/${SVCNAME}" ]] && return
	local x= services=

	for x in $(dolisting "${svcdir}/scheduled/${SVCNAME}/") ; do
		services="${services} ${x##*/}"
	done
		
	for x in ${services} ; do
		service_stopped "${x}" && start_service "${x}"
		rm -f "${svcdir}/scheduled/${SVCNAME}/${x}"
	done

	rmdir "${svcdir}/scheduled/${SVCNAME}"
}

svc_stop() {
	local x= mydep= mydeps= retval=0
	local -a servicelist=()

	# Do not try to stop if it had already failed to do so
	if is_runlevel_stop && service_failed "${SVCNAME}" ; then
		return 1
	elif service_stopped "${SVCNAME}" ; then
		ewarn "WARNING:  ${SVCNAME} has not yet been started."
		return 0
	fi
	if ! mark_service_stopping "${SVCNAME}" ; then
		eerror "ERROR:  ${SVCNAME} is already stopping."
		return 1
	fi
	
	# Ensure that we clean up if we abort for any reason
	trap "svc_quit" INT QUIT TSTP

	mark_service_starting "${SVCNAME}"
	
	# Store our e* messages in a buffer so we pretty print when parallel
	[[ ${RC_PARALLEL_STARTUP} == "yes" && ${RC_QUIET} != "yes" ]] \
		&& ebuffer "${svcdir}/ebuffer/${SVCNAME}"

	veinfo "Service ${SVCNAME} stopping"

	if in_runlevel "${SVCNAME}" "${BOOTLEVEL}" && \
	   [[ ${SOFTLEVEL} != "reboot" && ${SOFTLEVEL} != "shutdown" && \
	      ${SOFTLEVEL} != "single" ]] ; then
		ewarn "WARNING:  you are stopping a boot service."
	fi

	if [[ ${svcpause} != "yes" && ${RC_NO_DEPS} != "yes" ]] \
		&& ! service_wasinactive "${SVCNAME}" ; then
		if net_service "${SVCNAME}" ; then 
			if is_runlevel_stop || ! is_net_up "${SVCNAME}" ; then
				mydeps="net"
			fi
		fi
		mydeps="${mydeps} ${SVCNAME}"
	fi

	# Save the IN_BACKGROUND var as we need to clear it for stopping depends
	local ib_save="${IN_BACKGROUND}"
	unset IN_BACKGROUND

	for mydep in ${mydeps} ; do
		for x in $(needsme "${mydep}") ; do
			if service_started "${x}" || service_inactive "${x}" ; then
				stop_service "${x}"
			fi
			service_list=( "${service_list[@]}" "${x}" )
		done
	done

	for x in "${service_list[@]}" ; do
		service_stopped "${x}" && continue
		wait_service "${x}"
		if ! service_stopped "${x}" ; then
			eerror "ERROR:  cannot stop ${SVCNAME} as ${x} is still up."
			retval=1
			break
		fi
	done

	IN_BACKGROUND="${ib_save}"

	if [[ ${retval} == "0" ]] ; then
		# Now that deps are stopped, stop our service
		veindent
		(
		cd /
		[[ ${RC_QUIET} == "yes" ]] && RC_QUIET_STDOUT="yes"
		exit() {
			eerror "DO NOT USE EXIT IN INIT.D SCRIPTS"
			eerror "This IS a bug, please fix your broken init.d"
			unset -f exit
			exit "$@"
		}
		stop
		)
		retval="$?"

		# Don't trust init scripts to reset indentation properly
		# Needed for ebuffer
		eoutdent 99999

		# If a service has been marked inactive, exit now as something
		# may attempt to start it again later
		if [[ ${retval} == "0" ]] && service_inactive "${SVCNAME}" ; then
			svcinactive=0
			return 0
		fi
	fi

	if [[ ${retval} != 0 ]] ; then
		# Did we fail to stop? create symlink to stop multible attempts at
		# runlevel change.  Note this is only used at runlevel change ...
		is_runlevel_stop && mark_service_failed "${SVCNAME}"
		
		# If we are halting the system, do it as cleanly as possible
		if [[ ${SOFTLEVEL} == "reboot" || ${SOFTLEVEL} == "shutdown" ]] ; then
			mark_service_stopped "${SVCNAME}"
		else
			if [[ ${svcinactive} == "0" ]] ; then
				mark_service_inactive "${SVCNAME}"
			else
				mark_service_started "${SVCNAME}"
			fi
		fi

		eerror "ERROR:  ${SVCNAME} failed to stop"
	else
		svcstarted=1
		if service_inactive "${SVCNAME}" ; then
			svcinactive=0
		else
			mark_service_stopped "${SVCNAME}"
		fi

		veinfo "Service ${SVCNAME} stopped"
	fi

	# Flush the ebuffer 
	if [[ ${RC_PARALLEL_STARTUP} == "yes" && ${RC_QUIET} != "yes" ]] ; then
		eflush
		ebuffer ""
	fi

	# Reset the trap
	svc_trap
	
	return "${retval}"
}

svc_start() {
	local x= y= retval=0 startinactive=

	# Do not try to start if i have done so already on runlevel change
	if is_runlevel_start && service_failed "${SVCNAME}" ; then
		return 1
	elif service_started "${SVCNAME}" ; then
		ewarn "WARNING:  ${SVCNAME} has already been started."
		return 0
	elif service_inactive "${SVCNAME}" ; then
		if [[ ${IN_BACKGROUND} != "true" \
		&& ${IN_BACKGROUND} != "1" ]] ; then
			ewarn "WARNING:  ${SVCNAME} has already been started."
			return 0
		fi
	fi

	if ! mark_service_starting "${SVCNAME}" ; then
		if service_stopping "${SVCNAME}" ; then
			eerror "ERROR:  ${SVCNAME} is already stopping."
		else
			eerror "ERROR:  ${SVCNAME} is already starting."
		fi
		return 1
	fi

	# Ensure that we clean up if we abort for any reason
	trap "svc_quit" INT QUIT TSTP

	# Store our e* messages in a buffer so we pretty print when parallel
	[[ ${RC_PARALLEL_STARTUP} == "yes" && ${RC_QUIET} != "yes" ]] \
		&& ebuffer "${svcdir}/ebuffer/${SVCNAME}"

	veinfo "Service ${SVCNAME} starting"

	if broken "${SVCNAME}" ; then
		eerror "ERROR:  Some services needed are missing.  Run"
		eerror "        './${SVCNAME} broken' for a list of those"
		eerror "        services.  ${SVCNAME} was not started."
		retval=1	
	fi

	# Save the IN_BACKGROUND var as we need to clear it for starting depends
	local ib_save="${IN_BACKGROUND}"
	unset IN_BACKGROUND

	if [[ ${retval} == "0" && ${RC_NO_DEPS} != "yes" ]] ; then
		local startupservices="$(ineed "${SVCNAME}") $(valid_iuse "${SVCNAME}")"
		local netservices=
		for x in $(dolisting "/etc/runlevels/${BOOTLEVEL}/net.*") \
			$(dolisting "/etc/runlevels/${mylevel}/net.*") \
			$(dolisting "/var/lib/init.d/coldplugged/net.*") ; do 
			netservices="${netservices} ${x##*/}"
		done

		# Start dependencies, if any.
		if ! is_runlevel_start ; then
			for x in ${startupservices} ; do
				if [[ ${x} == "net" ]] && ! net_service "${SVCNAME}" \
					&& ! is_net_up ; then
					for y in ${netservices} ; do
						service_stopped "${y}" && start_service "${y}"
					done
				elif [[ ${x} != "net" ]] ; then
					service_stopped "${x}" && start_service "${x}"
				fi
			done
		fi

		# We also wait for any services we're after to finish incase they
		# have a "before" dep but we don't dep on them.
		if is_runlevel_start ; then
			startupservices="${startupservices} $(valid_iafter "${SVCNAME}")"
			if net_service "${SVCNAME}" ; then
				startupservices="${startupservices} $(valid_iafter "net")"
			fi
		fi

		if [[ " ${startupservices} " == *" net "* ]] ; then
			startupservices=" ${startupservices} "
			startupservices="${startupservices/ net / ${netservices} }"
			startupservices="${startupservices// net /}"
		fi

		# Wait for dependencies to finish.
		for x in ${startupservices} ; do
			service_started "${x}" && continue
			! service_inactive "${x}" && wait_service "${x}"
			if ! service_started "${x}" ; then
				# A 'need' dependency is critical for startup
				if ineed -t "${SVCNAME}" "${x}" >/dev/null \
					|| ( net_service "${x}" && ineed -t "${SVCNAME}" net \
					&& ! is_net_up ) ; then
					if service_inactive "${x}" || service_wasinactive "${x}" || \
						[[ -n $(dolisting "${svcdir}"/scheduled/*/"${x}") ]] ; then
						svc_schedule_start "${x}" "${SVCNAME}"
						[[ -n ${startinactive} ]] && startinactive="${startinactive}, "
						startinactive="${startinactive}${x}"
					else
						eerror "ERROR:  cannot start ${SVCNAME} as ${x} could not start"
						retval=1
						break
					fi
				fi
			fi
		done

		if [[ -n ${startinactive} && ${retval} == "0" ]] ; then
			# Change the last , to or for correct grammar.
			x="${startinactive##*, }"
			startinactive="${startinactive/%, ${x}/ or ${x}}"
			ewarn "WARNING:  ${SVCNAME} is scheduled to start when ${startinactive} has started."
			retval=1
		fi
	fi
		
	if [[ ${retval} == "0" ]] ; then
		IN_BACKGROUND="${ib_save}"
		veindent
		(
		cd /
		[[ ${RC_QUIET} == "yes" ]] && RC_QUIET_STDOUT="yes"
		exit() {
			eerror "DO NOT USE EXIT IN INIT.D SCRIPTS"
			eerror "This IS a bug, please fix your broken init.d"
			unset -f exit
			exit "$@"
		}

		# Apply any ulimits if defined
		[[ -n ${RC_ULIMIT} ]] && ulimit ${RC_ULIMIT}
		
		start
		)
		retval="$?"

		# Don't trust init scripts to reset indentation properly
		# Needed for ebuffer
		eoutdent 99999

		# If a service has been marked inactive, exit now as something
		# may attempt to start it again later
		if [[ ${retval} == "0" ]] && service_inactive "${SVCNAME}" ; then
			svcinactive=0
			ewarn "WARNING:  ${SVCNAME} has started but is inactive"
			if [[ ${RC_PARALLEL_STARTUP} == "yes" && ${RC_QUIET} != "yes" ]] ; then
				eflush
				ebuffer ""
			fi
			return 1
		fi
	fi

	if [[ ${retval} != "0" ]] ; then
		if [[ ${svcinactive} == "0" ]] ; then
			mark_service_inactive "${SVCNAME}"
		else
			mark_service_stopped "${SVCNAME}"
		fi

		if [[ -z ${startinactive} ]] ; then
			is_runlevel_start && mark_service_failed "${SVCNAME}"
			eerror "ERROR:  ${SVCNAME} failed to start"
		fi
	else
		svcstarted=0
		mark_service_started "${SVCNAME}"
		veinfo "Service ${SVCNAME} started"
	fi

	# Flush the ebuffer
	if [[ ${RC_PARALLEL_STARTUP} == "yes" && ${RC_QUIET} != "yes" ]] ; then
		eflush
		ebuffer ""
	fi

	# Reset the trap
	svc_trap
	
	return "${retval}"
}

svc_restart() {
	if ! service_stopped "${SVCNAME}" ; then
		svc_stop || return "$?"
	fi
	svc_start
}

svc_status() {
	# The basic idea here is to have some sort of consistent
	# output in the status() function which scripts can use
	# as an generic means to detect status.  Any other output
	# should thus be formatted in the custom status() function
	# to work with the printed " * status:  foo".
	local efunc="" state=""

	# If we are effectively root, check to see if required daemons are running
	# and update our status accordingly
	[[ ${EUID} == 0 ]] && update_service_status "${SVCNAME}"

	if service_stopping "${SVCNAME}" ; then
		efunc="eerror"
		state="stopping"
	elif service_starting "${SVCNAME}" ; then
		efunc="einfo"
		state="starting"
	elif service_inactive "${SVCNAME}" ; then
		efunc="ewarn"
		state="inactive"
	elif service_started "${SVCNAME}" ; then
		efunc="einfo"
		state="started"
	else
		efunc="eerror"
		state="stopped"
	fi
	[[ ${RC_QUIET_STDOUT} != "yes" ]] \
		&& ${efunc} "status:  ${state}"

	status
	# Return 0 if started, otherwise 1
	[[ ${state} == "started" ]]
}

# set *after* wrap_rcscript, else we get duplicates.
opts="start stop restart"

source "${myscript}"

# make sure whe have valid $opts
if [[ -z ${opts} ]] ; then
	opts="start stop restart"
fi

svc_homegrown() {
	local x arg="$1"
	shift

	# Walk through the list of available options, looking for the
	# requested one.
	for x in ${opts} ; do
		if [[ ${x} == "${arg}" ]] ; then
			if typeset -F "${x}" &>/dev/null ; then
				# Run the homegrown function
				"${x}"

				return $?
			fi
		fi
	done
	x=""

	# If we're here, then the function wasn't in $opts.
	[[ -n $* ]] && x="/ $* "
	eerror "ERROR: wrong args ( "${arg}" ${x})"
	# Do not quote this either ...
	usage ${opts}
	exit 1
}

shift
if [[ $# -lt 1 ]] ; then
	eerror "ERROR: not enough args."
	usage ${opts}
	exit 1
fi
for arg in $* ; do
	case "${arg}" in
	--quiet)
		RC_QUIET="yes"
		RC_QUIET_STDOUT="yes"
		;;
# We check this in functions.sh ...
#	--nocolor)
#		RC_NOCOLOR="yes"
#		;;
	--nodeps)
		RC_NO_DEPS="yes"
		;;
	--verbose)
		RC_VERBOSE="yes"
		;;
	esac
done

retval=0
for arg in $* ; do
	case "${arg}" in
	stop)
		if [[ -e "${svcdir}/scheduled/${SVCNAME}" ]] ; then
			rm -Rf "${svcdir}/scheduled/${SVCNAME}"
		fi

		# Stoped from the background - treat this as a restart so that
		# stopped services come back up again when started.
		if [[ ${IN_BACKGROUND} == "true" ]] ; then
			rm -rf "${svcdir}/snapshot/$$"
			mkdir -p "${svcdir}/snapshot/$$"
			cp -pP "${svcdir}"/started/* "${svcdir}/snapshot/$$/"
			rm -f "${svcdir}/snapshot/$$/${SVCNAME}"
		fi
	
		svc_stop
		retval="$?"
		
		if [[ ${IN_BACKGROUND} == "true" ]] ; then
			for x in $(dolisting "${svcdir}/snapshot/$$/") ; do
				if [[ -x ${x} ]] && service_stopped "${x##*/}" ; then
					svc_schedule_start "${SVCNAME}" "${x##*/}"
				fi
			done
			rm -rf "${svcdir}/snapshot/$$"
		else
			rm -f "${svcdir}"/scheduled/*/"${SVCNAME}"
		fi

		;;
	start)
		svc_start
		retval="$?"
		service_started "${SVCNAME}" && svc_start_scheduled
		;;
	needsme|ineed|usesme|iuse|broken|iafter)
		trace_dependencies "-${arg}"
		;;
	status)
		svc_status
		retval="$?"
		;;
	zap)
		einfo "Manually resetting ${SVCNAME} to stopped state."
		mark_service_stopped "${SVCNAME}"
		;;
	restart)
		svcrestart="yes"

        # We don't kill child processes if we're restarting
		# This is especically important for sshd ....
		RC_KILL_CHILDREN="no"				
		
		# Create a snapshot of started services
		rm -rf "${svcdir}/snapshot/$$"
		mkdir -p "${svcdir}/snapshot/$$"
		cp -pP "${svcdir}"/started/* "${svcdir}/snapshot/$$/"
		rm -f "${svcdir}/snapshot/$$/${SVCNAME}"

		# Simple way to try and detect if the service use svc_{start,stop}
		# to restart if it have a custom restart() funtion.
		svcres=$(sed -ne '/[[:space:]]*restart[[:space:]]*()/,/}/ p' \
			"${myscript}" )
		if [[ -n ${svcres} ]] ; then
			if [[ ! ${svcres} =~ "svc_stop" \
				|| ! ${svcres} =~ "svc_start" ]] ; then
				echo
				ewarn "Please use 'svc_stop; svc_start' and not 'stop; start' to"
				ewarn "restart the service in its custom 'restart()' function."
				ewarn "Run ${SVCNAME} without arguments for more info."
				echo
				svc_restart
			else
				restart
			fi
		else
			restart
		fi
		retval="$?"

		[[ -e "${svcdir}/scheduled/${SVCNAME}" ]] \
			&& rm -Rf "${svcdir}/scheduled/${SVCNAME}"
	
		# Restart dependencies as well
		for x in $(dolisting "${svcdir}/snapshot/$$/") ; do
			if [[ -x ${x} ]] && service_stopped "${x##*/}" ; then
				if service_inactive "${SVCNAME}" \
					|| service_wasinactive "${SVCNAME}" ; then
					svc_schedule_start "${SVCNAME}" "${x##*/}"
					ewarn "WARNING:  ${x##*/} is scheduled to start when ${SVCNAME} has started."
				elif service_started "${SVCNAME}" ; then
					start_service "${x##*/}"
				fi
			fi
		done
		rm -rf "${svcdir}/snapshot/$$"
	
		service_started "${SVCNAME}" && svc_start_scheduled

		# Wait for services to come up
		[[ ${RC_PARALLEL_STARTUP} == "yes" ]] && wait

		svcrestart="no"
		;;
	pause)
		svcpause="yes"
		svc_stop
		retval="$?"
		svcpause="no"
		;;
	--quiet|--nocolor|--nodeps|--verbose)
		;;
	help)
		exec "${svclib}"/sh/rc-help.sh "${myscript}" help
		;;
	*)
		# Allow for homegrown functions
		svc_homegrown ${arg}
		retval="$?"
		;;
	esac
done

exit "${retval}"

# vim:ts=4
