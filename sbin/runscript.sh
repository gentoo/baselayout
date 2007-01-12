#!/bin/bash
# Copyright 1999-2007 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

[[ " $* " == *" --debug "* ]] && set -x

if [[ $1 == "/"* ]] ; then
	myscript="$1"
else
	myscript="${PWD}/$1"
fi
cd /

# Common functions
[[ ${RC_GOT_FUNCTIONS} != "yes" ]] && . /sbin/functions.sh

# User must be root to run most script stuff (except status)
if [[ ${EUID} != "0" ]] && ! [[ $2 == "status" && $# -eq 2 ]] ; then
	eerror "$0:" $"must be root to run init scripts"
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
	trap 'eerror $"ERROR:" " ${SVCNAME}" $"caught an interrupt"; eflush; rm -rf "${svcdir}/snapshot/$$"; exit 1' \
		INT QUIT TERM TSTP
}

# Setup a default trap
svc_trap

# coldplug events can trigger init scripts, but we don't want to run them
# until after rc sysinit has completed so we punt them to the boot runlevel
if [[ -e /dev/.rcsysinit ]] ; then
	eerror $"ERROR:  cannot run" "${SVCNAME}" $"until sysinit completes"
	[[ ${RC_COLDPLUG:-yes} != "yes" ]] && exit 1
	set -f
	for x in ${RC_PLUG_SERVICES} ; do
		[[ ${SVCNAME} == ${x} ]] && break
		[[ "!${SVCNAME}" == ${x} ]] && exit 1
	done
	eerror "${SVCNAME}" $"will be started in the" "${BOOTLEVEL}" $"runlevel"
	if [[ ! -L /dev/.rcboot/"${SVCNAME}" ]] ; then
		[[ ! -d /dev/.rcboot ]] && mkdir /dev/.rcboot
		ln -snf "$1" /dev/.rcboot/"${SVCNAME}"
	fi
	exit 1
fi

# Only hotplug if we're allowed to
if [[ ${IN_HOTPLUG} == "1" ]] ; then
	if [[ ${RC_HOTPLUG:-yes} != "yes" ]] ; then
		eerror "${SVCNAME}" $"is not allowed to be hotplugged"
		exit 1
	fi
	
	set -f
	for x in ${RC_PLUG_SERVICES} ; do
		[[ ${SVCNAME} == ${x} ]] && break
		if [[ "!${SVCNAME}" == ${x} ]] ; then
			eerror "${SVCNAME}" $"is not allowed to be hotplugged"
			exit 1
		fi
	done
	set +f
fi

# State variables
svcpause="no"
svcrestart="no"

# Functions to handle dependencies and services
[[ ${RC_GOT_SERVICES} != "yes" ]] && . "${svclib}/sh/rc-services.sh"
# Functions to control daemons
[[ ${RC_GOT_DAEMON} != "yes" ]] && . "${svclib}/sh/rc-daemon.sh"

# Check if the textdomain is non-default
search_lang="${LC_ALL:-${LC_MESSAGES:-${LANG}}}"
[[ -f ${TEXTDOMAINDIR}/${search_lang%.*}/LC_MESSAGES/${SVCNAME}.mo ]] \
	&& TEXTDOMAIN="${SVCNAME}"

# Now check script for syntax errors
rcscript_errors=$(bash -n "${myscript}" 2>&1) || {
	[[ -n ${rcscript_errors} ]] && echo "${rcscript_errors}" >&2
	eerror $"ERROR:" " $1" $"has syntax errors in it; aborting ..."
	end_service "${SVCNAME}"
	exit 1
}

# Source configuration files.
# (1) Source /etc/conf.d/${PREFIX} where ${PREFIX} is the first part of
#     ${SVCNAME} dot seperated. For example if net.eth0 then load net.
# (2) Source /etc/conf.d/${SVCNAME} to get initscript-specific
#     configuration (if it exists).
# (3) Source /etc/rc.conf to pick up potentially overriding
#     configuration, if the system administrator chose to put it
#     there (if it exists).
conf="${SVCNAME%%.*}"
if [[ -n ${conf} && ${conf} != "${SVCNAME}" ]] ; then
	conf=$(add_suffix "/etc/conf.d/${conf}")
	[[ -e ${conf} ]] && . "${conf}"
fi
conf=$(add_suffix "/etc/conf.d/${SVCNAME}")
[[ -e ${conf} ]] && . "${conf}"
conf=$(add_suffix /etc/rc.conf)
[[ -e ${conf} ]] && . "${conf}"

# If we're using strict dependencies, setup an easy to use function
if [[ ${RC_STRICT_DEPEND} == "yes" ]] ; then
	rc-depend() { /sbin/rc-depend --strict "$@"; }
fi

svc_quit() {
	eerror $"ERROR:" " ${SVCNAME}" $"caught an interrupt"
	eflush
	svc_in_control
	local in_control=$?
	rm -rf "${svcdir}/snapshot/$$" "${svcdir}/exclusive/${SVCNAME}.$$"
	if [[ ${in_control} == 0 ]] ; then
		if service_wasinactive "${SVCNAME}" ; then
			mark_service_inactive "${SVCNAME}"
		elif [[ ${svcstarted} == "0" ]] ; then
			mark_service_started "${SVCNAME}"
		else
			mark_service_stopped "${SVCNAME}"
		fi
		end_service "${SVCNAME}"
	fi
	exit 1
}

usage() {
	local IFS="|"
	myline="${SVCNAME} { $* "
	unset IFS
	echo
	eerror $"Usage:" "${myline}}"
	eerror "       ${SVCNAME}" $"without arguments for full help"
}

stop() {
	# Return success so the symlink gets removed
	return 0
}

start() {
	eerror $"ERROR:" " ${SVCNAME}" $"does not have a start function."
	# Return failure so the symlink doesn't get created
	return 1
}

restart() {
	svc_stop || return $?
	svc_start
}

status() {
	# Dummy function
	return 0
}

svc_schedule_start() {
	local service="$1" start="$2" x=

	[[ ! -d "${svcdir}/scheduled/${service}" ]] \
		&& mkdir -p "${svcdir}/scheduled/${service}"
	ln -snf "/etc/init.d/${service}" \
		"${svcdir}/scheduled/${service}/${start}"

	for x in $(rc-depend --notrace -iprovide "${service}" ) ; do
		[[ ! -d "${svcdir}/scheduled/${x}" ]] \
			&& mkdir -p "${svcdir}/scheduled/${x}"
		ln -snf "/etc/init.d/${service}" "${svcdir}/scheduled/${x}/${start}"
	done

	mark_service_stopped "${start}"
	end_service "${start}"
}

svc_start_scheduled() {
	# If we're being started in the background, then don't
	# tie up the daemon that called us starting our scheduled services
	if [[ ${IN_BACKGROUND} == "true" || ${IN_BACKGROUND} == "1" ]] ; then
		unset IN_BACKGROUND
		svc_start_scheduled &
		export IN_BACKGROUND=true
		return
	fi

	local x= y= services= provides=$(rc-depend --notrace -iprovide "${SVCNAME}")
	for x in "${SVCNAME}" ${provides} ; do
		for y in $(dolisting "${svcdir}/scheduled/${x}/") ; do
			services="${services} ${y##*/}"
		done
	done

	if [[ -n ${services} ]] ; then
		for x in $(rc-depend -ineed -iuse ${services}) ; do
			service_stopped "${x}" && start_service "${x}"
			rm -f "${svcdir}/scheduled/${SVCNAME}/${x}"
			for y in ${provides} ; do
				rm -f "${svcdir}/scheduled/${y}/${x}"
			done
		done
	fi

	for x in "${SVCNAME}" ${provides} ; do
		rmdir "${svcdir}/scheduled/${x}" 2>/dev/null
	done
}

# Tests to see if we are still in control or not as we
# could have re-entered instantly blocking our inactive check
svc_in_control() {
	local x
	for x in starting started stopping ; do
		[[ "${svcdir}/${x}/${SVCNAME}" -nt "${svcdir}/exclusive/${SVCNAME}.$$" ]] \
				&& return 1
	done
	return 0
}

svc_stop() {
	local x= retval=0
	local -a servicelist=()

	# Do not try to stop if it had already failed to do so
	if is_runlevel_stop && service_failed "${SVCNAME}" ; then
		return 1
	elif service_stopped "${SVCNAME}" ; then
		[[ ${svcrestart} != "yes" ]] \
		&& ewarn $"WARNING:" " ${SVCNAME}" $"has not yet been started."
		return 0
	fi

	if ! mark_service_stopping "${SVCNAME}" ; then
		eerror $"ERROR:" " ${SVCNAME}" $"is already stopping."
		return 1
	fi

	svcstarted=0
	# Ensure that we clean up if we abort for any reason
	trap "svc_quit" INT QUIT TERM TSTP

	mark_service_starting "${SVCNAME}"
	begin_service "${SVCNAME}" 

	# This is our mtime file to work out if we're still in control or not
	touch "${svcdir}/exclusive/${SVCNAME}.$$"

	# Store our e* messages in a buffer so we pretty print when parallel
	[[ ${RC_PARALLEL_STARTUP} == "yes" && ${RC_QUIET} != "yes" ]] \
		&& ebuffer "${svcdir}/ebuffer/${SVCNAME}"

	veinfo $"Service" "${SVCNAME}" $"stopping"

	if in_runlevel "${SVCNAME}" "${BOOTLEVEL}" && \
	   [[ ${SOFTLEVEL} != "reboot" && ${SOFTLEVEL} != "shutdown" && \
	      ${SOFTLEVEL} != "single" ]] ; then
		ewarn $"WARNING: you are stopping a boot service."
	fi

	# Save the IN_BACKGROUND var as we need to clear it for stopping depends
	local ib_save="${IN_BACKGROUND}"
	unset IN_BACKGROUND

	if [[ ${svcpause} != "yes" && ${RC_NO_DEPS} != "yes" ]] \
		&& ! service_wasinactive "${SVCNAME}" ; then
		for x in $(reverse_list $(rc-depend -needsme "${SVCNAME}")) ; do
			if service_started "${x}" || service_inactive "${x}" ; then
				stop_service "${x}"
			fi
			service_list=( "${service_list[@]}" "${x}" )
		done

		for x in "${service_list[@]}" ; do
			local retry=3
			while [[ ${retry} -gt 0 ]] ; do
				service_stopped "${x}" && break
				wait_service "${x}"
				((retry--))
			done
			if ! service_stopped "${x}" ; then
				eerror $"ERROR:" $"cannot stop" "${SVCNAME}" $"as" "${x}" $"is still up."
				retval=1
				break
			fi
		done

		# Work with uses, before and after deps too, but as they are not needed
		# we cannot explicitly stop them.
		# We use -needsme with -usesme so we get the full dep list.
		# We use --notrace with -ibefore to stop circular deps.
		for x in $(rc-depend -needsme -usesme "${SVCNAME}") \
			$(rc-depend --notrace -ibefore "${SVCNAME}"); do
			service_stopping "${x}" && wait_service "${x}"
		done
	fi

	IN_BACKGROUND="${ib_save}"

	if [[ ${retval} == "0" ]] ; then
		# Now that deps are stopped, stop our service
		veindent
		(
		[[ ${RC_QUIET} == "yes" ]] && RC_QUIET_STDOUT="yes"
		exit() {
			eerror $"DO NOT USE EXIT IN INIT.D SCRIPTS"
			eerror $"This IS a bug, please fix your broken init.d"
			unset -f exit
			exit "$@"
		}
		stop
		)
		retval=$?

		# Don't trust init scripts to reset indentation properly
		# Needed for ebuffer
		eoutdent 99999

		# If a service has been marked inactive, exit now as something
		# may attempt to start it again later
		if [[ ${retval} == "0" ]] ; then
			if service_inactive "${SVCNAME}" || ! svc_in_control ; then
				rm -f "${svcdir}/exclusive/${SVCNAME}.$$"
				return 0
			fi
		fi
	fi

	if [[ ${retval} != 0 ]] ; then
		# Did we fail to stop? create symlink to stop multible attempts at
		# runlevel change.  Note this is only used at runlevel change ...
		is_runlevel_stop && mark_service_failed "${SVCNAME}"
		
		# If we are halting the system, do it as cleanly as possible
		case ${SOFTLEVEL} in
			reboot|shutdown|single)
				mark_service_stopped "${SVCNAME}"
				;;
			*)
				if service_wasinactive "${SVCNAME}" ; then
					mark_service_inactive "${SVCNAME}"
				else
					mark_service_started "${SVCNAME}"
				fi
				;;
		esac

		eerror $"ERROR:" " ${SVCNAME}" $"failed to stop"
	else
		svcstarted=1
		service_inactive "${SVCNAME}" || mark_service_stopped "${SVCNAME}"
		veinfo $"Service" "${SVCNAME}" $"stopped"
	fi

	# Flush the ebuffer 
	if [[ ${RC_PARALLEL_STARTUP} == "yes" && ${RC_QUIET} != "yes" ]] ; then
		eflush
		ebuffer ""
	fi

	rm -f "${svcdir}/exclusive/${SVCNAME}.$$"
	end_service "${SVCNAME}"

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
		ewarn $"WARNING:" " ${SVCNAME}" $"has already been started."
		return 0
	elif service_inactive "${SVCNAME}" ; then
		if [[ ${IN_BACKGROUND} != "true" \
		&& ${IN_BACKGROUND} != "1" ]] ; then
			ewarn $"WARNING:" " ${SVCNAME}" $"has already been started."
			return 0
		fi
	else
		case ${SOFTLEVEL} in
			reboot|shutdown|single)
				ewarn $"WARNING:  system shutting down, will not start" "${SVCNAME}"
				return 1
				;;
		esac
	fi

	if ! mark_service_starting "${SVCNAME}" ; then
		if service_stopping "${SVCNAME}" ; then
			eerror $"ERROR:" " ${SVCNAME}" $"is already stopping."
		else
			eerror $"ERROR: "" ${SVCNAME}" $"is already starting."
		fi
		return 1
	fi

	svcstarted=1
	# Ensure that we clean up if we abort for any reason
	trap "svc_quit" INT QUIT TERM TSTP
	begin_service "${SVCNAME}"

	# This is our mtime file to work out if we're still in control or not
	touch "${svcdir}/exclusive/${SVCNAME}.$$"

	# Store our e* messages in a buffer so we pretty print when parallel
	[[ ${RC_PARALLEL_STARTUP} == "yes" && ${RC_QUIET} != "yes" ]] \
		&& ebuffer "${svcdir}/ebuffer/${SVCNAME}"

	veinfo $"Service" "${SVCNAME}" $"starting"

	if [[ -n $(rc-depend --notrace -broken "${SVCNAME}") ]] ; then
		eerror $"ERROR:  Some services needed are missing.  Run"
		eerror "        ""'./${SVCNAME}" $"broken' for a list of those"
		eerror "        " $"services."  "${SVCNAME}" $"was not started."
		retval=1	
	fi

	# Save the IN_BACKGROUND var as we need to clear it for starting depends
	local ib_save="${IN_BACKGROUND}"
	unset IN_BACKGROUND

	if [[ ${retval} == "0" && ${RC_NO_DEPS} != "yes" ]] ; then
		# Start dependencies, if any.
		local startsvc=$(rc-depend -ineed -iuse "${SVCNAME}")
		if ! is_runlevel_start ; then
			for x in ${startsvc} ; do
				service_stopped "${x}" && start_service "${x}"
			done
		fi

		# Wait for dependencies to finish.
		local ineed=$(rc-depend --notrace -ineed "${SVCNAME}")
		for x in ${startsvc} $(rc-depend -iafter "${SVCNAME}") ; do
			local timeout=3
			while [[ ${timeout} -gt 0 ]] ; do
				service_started "${x}" && continue 2
				wait_service "${x}"
				service_started "${x}" && continue 2
				if service_inactive "${x}" || service_scheduled "${x}" ; then
					if [[ " ${startsvc} " == *" ${x} "* ||
						" ${ineed} " == *" $(rc-depend --notrace -iprovide "${x}") " ]] ; then
						svc_schedule_start "${x}" "${SVCNAME}"
						[[ -n ${startinactive} ]] && startinactive="${startinactive}, "
						startinactive="${startinactive}${x}"
					fi

					continue 2
				fi
				service_stopped "${x}" && break

				# Small pause before trying again as it should be starting
				# if we get here
				sleep 1
				((timeout--))
			done

			[[ " ${ineed} " != *" ${x} "*  ]] && continue
		
			eerror "ERROR:" $"cannot start" "${SVCNAME}" $"as" "${x}" $"could not start"
			retval=1
			break
		done

		if [[ -n ${startinactive} && ${retval} == "0" ]] ; then
			# Change the last , to or for correct grammar.
			x="${startinactive##*, }"
			startinactive="${startinactive/%, ${x}/ or ${x}}"
			ewarn "WARNING:" " ${SVCNAME}" $"is scheduled to start when" "${startinactive}" $"has started."
			retval=1
		fi
	fi
		
	if [[ ${retval} == "0" ]] ; then
		IN_BACKGROUND="${ib_save}"
		veindent
		(
		[[ ${RC_QUIET} == "yes" ]] && RC_QUIET_STDOUT="yes"
		exit() {
			eerror $"DO NOT USE EXIT IN INIT.D SCRIPTS"
			eerror $"This IS a bug, please fix your broken init.d"
			unset -f exit
			exit "$@"
		}

		# Apply any ulimits if defined
		[[ -n ${RC_ULIMIT} ]] && ulimit ${RC_ULIMIT}
		
		start
		)
		retval=$?

		# Don't trust init scripts to reset indentation properly
		# Needed for ebuffer
		eoutdent 99999

		# If a service has been marked inactive, exit now as something
		# may attempt to start it again later
		if [[ ${retval} == "0" ]] ; then
			if service_inactive "${SVCNAME}" || ! svc_in_control ; then
				rm -f "${svcdir}/exclusive/${SVCNAME}.$$"
				ewarn $"WARNING:" " ${SVCNAME}" $"has started but is inactive"
				if [[ ${RC_PARALLEL_STARTUP} == "yes" && ${RC_QUIET} != "yes" ]] ; then
					eflush
					ebuffer ""
				fi
				return 1
			fi
		fi
	fi

	if [[ ${retval} != "0" ]] ; then
		if service_wasinactive "${SVCNAME}" ; then
			mark_service_inactive "${SVCNAME}"
		elif [[ -z ${startinactive} ]] ; then
			mark_service_stopped "${SVCNAME}"
			is_runlevel_start && mark_service_failed "${SVCNAME}"
			eerror $"ERROR:" " ${SVCNAME}" $"failed to start"
		fi
	else
		svcstarted=0
		mark_service_started "${SVCNAME}"
		veinfo $"Service" "${SVCNAME}" $"started"
	fi

	# Flush the ebuffer
	if [[ ${RC_PARALLEL_STARTUP} == "yes" && ${RC_QUIET} != "yes" ]] ; then
		eflush
		ebuffer ""
	fi

	rm -f "${svcdir}/exclusive/${SVCNAME}.$$"
	end_service "${SVCNAME}"

	# Reset the trap
	svc_trap
	
	return "${retval}"
}

svc_restart() {
	case ${SOFTLEVEL} in
		reboot|shutdown|single)
			ewarn $"WARNING:  system shutting down, will not restart" "${SVCNAME}"
			return 1
			;;
	esac
	
	# Create a snapshot of started services
	rm -rf "${svcdir}/snapshot/$$"
	mkdir -p "${svcdir}/snapshot/$$"
	cp -pPR "${svcdir}"/started/* "${svcdir}"/inactive/* \
		"${svcdir}/snapshot/$$/" 2>/dev/null
	rm -f "${svcdir}/snapshot/$$/${SVCNAME}"

	svcrestart="yes"
	# Simple way to try and detect if the service use svc_{start,stop}
	# to restart if it have a custom restart() funtion.
	svcres=$(sed -ne '/^[[:space:]]*restart[[:space:]]*()/,/^[[:space:]]*}/ p' "${myscript}")
	if [[ -n ${svcres} ]] ; then
		if [[ ! ${svcres} =~ svc_stop \
			|| ! ${svcres} =~ svc_start ]] ; then
			echo ${svcres}
			ewarn $"Please use 'svc_stop; svc_start' and not 'stop; start' to"
			ewarn $"restart the service in its custom 'restart()' function."
			ewarn $"Run" "${SVCNAME}" $"without arguments for more info."
			echo
			svc_stop && svc_start 
		else
			restart
		fi
	else
		restart
	fi
	retval=$?
	svcrestart="no"

	[[ -e "${svcdir}/scheduled/${SVCNAME}" ]] \
		&& rm -Rf "${svcdir}/scheduled/${SVCNAME}"

	# Restart dependencies as well
	local x=
	for x in $(dolisting "${svcdir}/snapshot/$$/") ; do
		if [[ -x ${x} ]] && service_stopped "${x##*/}" ; then
			if service_inactive "${SVCNAME}" \
				|| service_wasinactive "${SVCNAME}" ; then
				svc_schedule_start "${SVCNAME}" "${x##*/}"
				ewarn $"WARNING:" " ${x##*/}" $"is scheduled to start when" "${SVCNAME}" $"has started."
			elif service_started "${SVCNAME}" ; then
				start_service "${x##*/}"
			fi
		fi
	done
	rm -rf "${svcdir}/snapshot/$$"

	service_started "${SVCNAME}" && svc_start_scheduled

	# Wait for services to come up
	if [[ ${IN_BACKGROUND} != "true" \
		&& ${IN_BACKGROUND} != "1" ]] ; then
		[[ ${RC_PARALLEL_STARTUP} == "yes" ]] && wait
	fi

	return 0
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
		state=$"stopping"
	elif service_starting "${SVCNAME}" ; then
		efunc="einfo"
		state=$"starting"
	elif service_inactive "${SVCNAME}" ; then
		efunc="ewarn"
		state=$"inactive"
	elif service_started "${SVCNAME}" ; then
		efunc="einfo"
		state=$"started"
	else
		efunc="eerror"
		state=$"stopped"
	fi
	[[ ${RC_QUIET_STDOUT} != "yes" ]] \
		&& ${efunc} $"status:" "${state}"

	status
	# Return 0 if started, otherwise 1
	[[ ${state} == "started" ]]
}

# set *after* wrap_rcscript, else we get duplicates.
opts="start stop restart"

. "${myscript}"

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
	eerror $"ERROR:" $"wrong args" "( "${arg}" ${x})"
	# Do not quote this either ...
	usage ${opts}
	exit 1
}

shift
if [[ $# -lt 1 ]] ; then
	eerror $"ERROR:" $"not enough args."
	usage ${opts}
	exit 1
fi
for arg in "$@" ; do
	case ${arg} in
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
for arg in "$@" ; do
	case ${arg} in
	stop)
		if [[ -e "${svcdir}/scheduled/${SVCNAME}" ]] ; then
			rm -Rf "${svcdir}/scheduled/${SVCNAME}"
		fi

		# Stoped from the background - treat this as a restart so that
		# stopped services come back up again when started.
		if [[ ${IN_BACKGROUND} == "true" || ${IN_BACKGROUND} == "1" ]] ; then
			rm -rf "${svcdir}/snapshot/$$"
			mkdir -p "${svcdir}/snapshot/$$"
			cp -pPR "${svcdir}"/started/* "${svcdir}"/inactive/* \
				"${svcdir}/snapshot/$$/" 2>/dev/null
			rm -f "${svcdir}/snapshot/$$/${SVCNAME}"
		fi
	
		svc_stop
		retval=$?
		
		if [[ ${IN_BACKGROUND} == "true" || ${IN_BACKGROUND} == "1" ]] ; then
			for x in $(dolisting "${svcdir}/snapshot/$$/") ; do
				if [[ -x ${x} ]] && service_stopped "${x##*/}" ; then
					svc_schedule_start "${SVCNAME}" "${x##*/}"
				fi
			done
			rm -rf "${svcdir}/snapshot/$$"
		elif service_stopped "${SVCNAME}" ; then
			rm -f "${svcdir}"/scheduled/*/"${SVCNAME}"
			if [[ ${SOFTLEVEL} != "single" ]] ; then
				rm -f "${svcdir}/coldplugged/${SVCNAME}"
			fi
		fi

		;;
	start)
		svc_start
		retval=$?
		service_started "${SVCNAME}" && svc_start_scheduled
		;;
	needsme|ineed|usesme|iuse|broken|iafter|iprovide)
		rc-depend "-${arg}" "${SVCNAME}"
		;;
	status)
		svc_status
		retval="$?"
		;;
	zap)
		einfo $"Manually resetting" "${SVCNAME}" $"to stopped state."
		mark_service_stopped "${SVCNAME}"
		;;
	restart)
		svc_restart
		retval=$?
		;;
	condrestart|conditionalrestart)
		if service_started "${SVCNAME}" ; then
			svc_restart
		fi
		retval=$?
		;;
	pause)
		svcpause="yes"
		svc_stop
		retval=$?
		svcpause="no"
		;;
	--quiet|--nocolor|--nocolour|--nodeps|--verbose|--debug)
		;;
	-V|--version)
		exec cat "${ROOT}"/etc/gentoo-release
		exit 1
		;;
	help|-h|--help)
		exec "${svclib}"/sh/rc-help.sh "${myscript}" help
		;;
	*)
		# Allow for homegrown functions
		svc_homegrown ${arg}
		retval=$?
		;;
	esac
done

exit ${retval}

# vim: set ts=4 :
