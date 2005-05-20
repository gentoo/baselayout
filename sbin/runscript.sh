#!/bin/bash
# Copyright 1999-2005 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header$

# Common functions
[[ ${RC_GOT_FUNCTIONS} != "yes" ]] && source /sbin/functions.sh
# Functions to handle dependencies and services
[[ ${RC_GOT_SERVICES} != "yes" ]] && source "${svclib}/sh/rc-services.sh"
# Functions to control daemons
[[ ${RC_GOT_DAEMON} != "yes" ]] && source "${svclib}/sh/rc-daemon.sh"

# User must be root to run most script stuff (except status)
if [[ ${EUID} != 0 ]] && ! [[ $2 == "status" && $# -eq 2 ]] ; then
	eerror "$0: must be root to run init scripts"
	exit 1
fi

# State variables
svcpause="no"
svcrestart="no"

myscript=$1
if [[ -L $1 ]] && [[ ! -L /etc/init.d/${1##*/} ]] ; then
	myservice=$(readlink "$1")
else
	myservice=$1
fi

myservice=${myservice##*/}
export SVCNAME=${myservice}
mylevel=$(<"${svcdir}/softlevel")


# Set $IFACE to the name of the network interface if it is a 'net.*' script
if [[ ${myservice%%.*} == "net" ]] && [[ ${myservice##*.} != ${myservice} ]] ; then
	IFACE=${myservice##*.}
	NETSERVICE="yes"
else
	IFACE=
	NETSERVICE=
fi

# We need to stop hotplug from launching net scripts until the boot level
# has completed
if [[ ${NETSERVICE} == "yes" && ${IFACE} != "lo" ]] ; then
       if [[ -z ${mylevel} || ${mylevel} == ${BOOTLEVEL} ]] ; then
               eerror "$0: cannot start until the runlevel "${BOOTLEVEL}" has completed"
               exit 1
       fi
fi

# Source configuration files.
# (1) Source /etc/conf.d/${myservice} to get initscript-specific
#     configuration (if it exists).
# (2) Source /etc/conf.d/net if it is a net.* service
# (3) Source /etc/rc.conf to pick up potentially overriding
#     configuration, if the system administrator chose to put it
#     there (if it exists).

[[ -e $(add_suffix /etc/conf.d/${myservice}) ]] && source "$(add_suffix /etc/conf.d/${myservice})"
[[ -e $(add_suffix /etc/conf.d/net) ]]          && \
[[ ${NETSERVICE} == "yes" ]]                    && source "$(add_suffix /etc/conf.d/net)"
[[ -e $(add_suffix /etc/rc.conf) ]]             && source "$(add_suffix /etc/rc.conf)"


usage() {
	local IFS="|"
	myline="Usage: ${myservice} { $* "
	echo
	eerror "${myline}}"
	eerror "       ${myservice} without arguments for full help"
}

stop() {
	# Return success so the symlink gets removed
	return 0
}

start() {
	eerror "ERROR:  \"${myservice}\" does not have a start function."
	# Return failure so the symlink doesn't get created
	return 1
}

restart() {
	svc_restart || return $?
}

status() {
	# Dummy function
	return 0
}
			
svc_stop() {
	local x=
	local mydep=
	local mydeps=
	local retval=0
	local ordservice=
	local was_inactive=false

	if service_stopping "${myservice}" ; then
		if [[ ${RC_QUIET_STDOUT} != "yes" ]] ; then
			eerror "ERROR:  \"${myservice}\" is already stopping."
			return 1
		else
			return 0
		fi
	fi
	
	if service_stopped "${myservice}" && ! service_inactive "${myservice}" ; then
		if [[ ${RC_QUIET_STDOUT} != "yes" ]] ; then
			eerror "ERROR:  \"${myservice}\" has not yet been started."
			return 1
		else
			return 0
		fi
	fi

	# Do not try to stop if it had already failed to do so on runlevel change
	if is_runlevel_stop && service_failed "${myservice}" ; then
		exit 1
	fi

	service_inactive "${myservice}" && was_inactive=true

	# Remove symlink to prevent recursion
	mark_service_stopping "${myservice}"

	service_message "Stopping service ${myservice}"

	if in_runlevel "${myservice}" "${BOOTLEVEL}" && \
	   [[ ${SOFTLEVEL} != "reboot" && ${SOFTLEVEL} != "shutdown" && \
	      ${SOFTLEVEL} != "single" ]]
	then
		ewarn "WARNING:  you are stopping a boot service."
	fi
	
	if [[ ${svcpause} != "yes" ]] ; then
		if [[ ${NETSERVICE} == "yes" ]] ; then
			# A net.* service
			if in_runlevel "${myservice}" "${BOOTLEVEL}" || \
			   in_runlevel "${myservice}" "${mylevel}"
			then
				# Only worry about net.* services if this is the last one running,
				# or if RC_NET_STRICT_CHECKING is set ...
				if ! is_net_up ; then
					mydeps="net"
				fi
			fi

			mydeps="${mydeps} ${myservice}"
		else
			mydeps=${myservice}
		fi
	fi

	for mydep in ${mydeps} ; do
		# If some service 'need' $mydep, stop it first; or if it is a runlevel change,
		# first stop all services that is started 'after' $mydep.
		if needsme "${mydep}" >/dev/null || \
		   (is_runlevel_stop && ibefore "${mydep}" >/dev/null)
		then
			local servicelist=$(needsme "${mydep}")

			# On runlevel change, stop all services "after $mydep" first ...
			is_runlevel_stop && servicelist="${servicelist} $(ibefore "${mydep}")"

			for x in ${servicelist} ; do
				# Make sure we have a relevant rc-script ...
				if [[ ${x} != "net" ]] && [[ ! -f /etc/init.d/${x} ]] ; then
					continue
				fi

				# Service not currently running, continue
				service_started "${x}" || continue

				if ibefore -t "${mydep}" "${x}" >/dev/null && \
				   [[ -L ${svcdir}/softscripts.new/${x} ]]
				then
					# Service do not 'need' $mydep, and is still present in
					# new runlevel ...
					continue
				fi

				stop_service "${x}"

				if [[ $? -ne 0 ]] ; then
					# If we are halting the system, try and get it down as
					# clean as possible, else do not stop our service if
					# a dependent service did not stop.
					if needsme -t "${mydep}" "${x}" >/dev/null && \
					   [[ ${SOFTLEVEL} != "reboot" && ${SOFTLEVEL} != "shutdown" ]]
					then
						retval=1
					fi

					break
				fi
			done
		fi
	done

	if [[ ${retval} -ne 0 ]] ; then
		eerror "ERROR:  problems stopping dependent services."
		eerror "        \"${myservice}\" is still up."
	else
		# Stop einfo/ebegin/eend from working as parallel messes us up
		[[ ${RC_PARALLEL_STARTUP} == "yes" ]] && RC_QUIET_STDOUT="yes"
		# Now that deps are stopped, stop our service
		( stop )
		retval=$?

		# If a service has been marked inactive, exit now as something
		# may attempt to start it again later
		service_inactive "${myservice}" && return 0
	fi

	if [[ ${retval} -ne 0 ]] ; then
		# Did we fail to stop? create symlink to stop multible attempts at
		# runlevel change.  Note this is only used at runlevel change ...
		if is_runlevel_stop ; then
			mark_service_failed "${myservice}"
		fi
		
		# If we are halting the system, do it as cleanly as possible
		if [[ ${SOFTLEVEL} != "reboot" && ${SOFTLEVEL} != "shutdown" ]] ; then
			mark_service_started "${myservice}"
			${was_inactive} && mark_service_inactive "${myservice}"
		fi
	else
		# If we're stopped from a daemon that sets ${IN_BACKGROUND} such as
		# wpa_monitor when we mark as inactive instead of taking the down
		if ${IN_BACKGROUND:-false} ; then
			mark_service_inactive "${myservice}"
		else
			mark_service_stopped "${myservice}"
		fi
	fi

	if [[ ${retval} == 0 ]]; then
		service_message "Stopped service ${myservice}"
	else
		service_message "eerror" "FAILED to stop service ${myservice}!"
	fi

	return "${retval}"
}

svc_start() {
	local retval=0
	local startfail="no"
	local x=
	local y=
	local myserv=
	local ordservice=

	if service_started "${myservice}" || service_starting "${myservice}" ; then
		if ! service_inactive "${myservice}" ; then
			if [[ ${RC_QUIET_STDOUT} != "yes" ]] ; then
				ewarn "WARNING:  \"${myservice}\" has already been started."
			fi

			return 0
		fi

		if service_stopping "${myservice}" ; then
			if [[ ${RC_QUIET_STDOUT} != "yes" ]] ; then
				ewarn "WARNING:  please wait for \"${myservice}\" to stop first."
			fi

			return 0
		fi
	fi

	# Do not try to start if i have done so already on runlevel change
	if is_runlevel_start && service_failed "${myservice}" ; then
		exit 1
	fi

	# Link first to prevent possible recursion
	mark_service_starting "${myservice}"

	service_message "Starting service ${myservice}"

	# On rc change, start all services "before $myservice" first
	if is_runlevel_start ; then
		startupservices="$(ineed "${myservice}") \
			$(valid_iuse "${myservice}") \
			$(valid_iafter "${myservice}")"
	else
		startupservices="$(ineed "${myservice}") \
			$(valid_iuse "${myservice}")"
	fi

	# Start dependencies, if any
	for x in ${startupservices} ; do
		if [[ ${x} == "net" ]] && [[ ${NETSERVICE} != "yes" ]] && ! is_net_up ; then
			local netservices="$(dolisting "/etc/runlevels/${BOOTLEVEL}/net.*") \
				$(dolisting "/etc/runlevels/${mylevel}/net.*")"

			for y in ${netservices} ; do
				mynetservice=${y##*/}

				start_service "${mynetservice}"

				# A 'need' dependency is critical for startup
				if [[ $? != 0 ]] && ineed -t "${myservice}" "${x}" >/dev/null ; then
					# Only worry about a net.* service if we do not have one
					# up and running already, or if RC_NET_STRICT_CHECKING
					# is set ....
					if ! is_net_up ; then
						startfail="yes"
					fi
				fi
			done	
		elif [[ ${x} != "net" ]] ; then
			start_service "${x}"

			# A 'need' dependacy is critical for startup
			if [[ $? != 0 ]] && ineed -t "${myservice}" "${x}" >/dev/null ; then
				startfail="yes"
			fi
		fi
	done

	# wait for dependencies to finish
	for x in ${startupservices} ; do
		if [ "${x}" = "net" -a "${NETSERVICE}" != "yes" ] ; then
			local netservices="$(dolisting "/etc/runlevels/${BOOTLEVEL}/net.*") \
			$(dolisting "/etc/runlevels/${mylevel}/net.*")"

			for y in ${netservices} ; do
				mynetservice="${y##*/}"

				wait_service "${mynetservice}"

				# A 'need' dependency is critical for startup
				if [ "$?" -ne 0 ] && ineed -t "${myservice}" "${x}" >/dev/null ; then
					# Only worry about a net.* service if we do not have one
					# up and running already, or if RC_NET_STRICT_CHECKING
					# is set ....
					if ! is_net_up ; then
						startfail="yes"
					fi
				fi
			done
		elif [ "${x}" != "net" ] ; then
			wait_service "${x}"
			# A 'need' dependacy is critical for startup
			if [ "$?" -ne 0 ] && ineed -t "${myservice}" "${x}" >/dev/null ; then
				startfail="yes"
			fi
		fi
	done
	
	if [[ ${startfail} == "yes" ]] ; then
		eerror "ERROR:  Problem starting needed services."
		eerror "        \"${myservice}\" was not started."
		retval=1
	fi

	# Start service
	if [[ ${retval} -eq 0 ]] && broken "${myservice}" ; then
		eerror "ERROR:  Some services needed are missing.  Run"
		eerror "        './${myservice} broken' for a list of those"
		eerror "        services.  \"${myservice}\" was not started."
		retval=1
	elif [[ ${retval} -eq 0 ]] && ! broken "${myservice}" ; then
		(
		exit() {
			RC_QUIET_STDOUT="no"
			eerror "DO NOT USE EXIT IN INIT.D SCRIPTS"
			eerror "This IS a bug, please fix your broken init.d"
			unset -f exit
			exit $@
		}
		# Stop einfo/ebegin/eend from working as parallel messes us up
		[[ ${RC_PARALLEL_STARTUP} == "yes" ]] && RC_QUIET_STDOUT="yes"
		start
		)
		retval=$?
		# If a service has been marked inactive, exit now as something
		# may attempt to start it again later
		service_inactive "${myservice}" && return 0
	fi

	if [[ ${retval} -ne 0 ]] && is_runlevel_start ; then
		mark_service_failed "${myservice}"
	fi

	# Remove link if service didn't start; but only if we're not booting
	# if we're booting, we need to continue and do our best to get the
	# system up.
	if [[ ${retval} -ne 0 ]] && [[ ${SOFTLEVEL} != ${BOOTLEVEL} ]] ; then
		mark_service_stopped "${myservice}"
	elif [[ ${retval} -eq 0 ]] ; then
		mark_service_started "${myservice}"
	fi

	if [[ ${retval} == 0 ]]; then
		service_message "Service ${myservice} started OK"
	else
		service_message "eerror" "FAILED to start service ${myservice}!"
	fi

	return "${retval}"
}

svc_restart() {
	if service_started "${myservice}" ; then
		svc_stop || return "$?"
		sleep 1
	fi

	svc_start || return "$?"
}

svc_status() {
	# The basic idea here is to have some sort of consistent
	# output in the status() function which scripts can use
	# as an generic means to detect status.  Any other output
	# should thus be formatted in the custom status() function
	# to work with the printed " * status:  foo".
	local efunc="" state=""

	if service_starting "${myservice}" ; then
		efunc="einfo"
		state="starting"
	elif service_inactive "${myservice}" ; then
		efunc="ewarn"
		state="inactive"
	elif service_started "${myservice}" ; then
		efunc="einfo"
		state="started"
	elif service_stopping "${myservice}" ; then
		efunc="eerror"
		state="stopping"
	else
		efunc="eerror"
		state="stopped"
	fi
	[[ ${RC_QUIET_STDOUT} != "yes" ]] \
		&& ${efunc} "status:  ${state}"

	status
	[[ ${efunc} != "eerror" ]]
}

rcscript_errors=$(bash -n "${myscript}" 2>&1) || {
	[[ -n ${rcscript_errors} ]] && echo "${rcscript_errors}" >&2
	eerror "ERROR:  \"${myscript}\" has syntax errors in it; aborting ..."
	exit 1
}

# set *after* wrap_rcscript, else we get duplicates.
opts="start stop restart"

source "${myscript}"

# make sure whe have valid $opts
if [[ -z ${opts} ]] ; then
	opts="start stop restart"
fi

svc_homegrown() {
	local arg=$1
	local x=

	# Walk through the list of available options, looking for the
	# requested one.
	for x in ${opts} ; do
		if [[ ${x} == ${arg} ]] ; then
			if typeset -F "${x}" &>/dev/null ; then
				# Run the homegrown function
				"${x}"

				return $?
			fi
		fi
	done

	# If we're here, then the function wasn't in $opts.
	eerror "ERROR:  wrong args. (  "${arg}" / $* )"
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
		RC_QUIET_STDOUT="yes"
		;;
# We check this in functions.sh ...
#	--nocolor)
#		RC_NOCOLOR="yes"
#		;;
	--verbose)
		RC_VERBOSE="yes"
		;;
	esac
done
for arg in $* ; do
	case "${arg}" in
	stop)
		svc_stop
		;;
	start)
		svc_start
		;;
	needsme|ineed|usesme|iuse|broken)
		trace_dependencies "-${arg}"
		;;
	status)
		svc_status
		;;
	zap)
		if service_started "${myservice}" || service_starting "${myservice}" ; then
			einfo "Manually resetting ${myservice} to stopped state."
			mark_service_stopped "${myservice}"
		fi
		;;
	restart)
		svcrestart="yes"

		# Create a snapshot of started services
		rm -rf "${svcdir}/snapshot/$$"
		mkdir -p "${svcdir}/snapshot/$$"
		cp -a "${svcdir}"/started/* "${svcdir}/snapshot/$$/"

		# Simple way to try and detect if the service use svc_{start,stop}
		# to restart if it have a custom restart() funtion.
		if [[ -n $(egrep '^[[:space:]]*restart[[:space:]]*()' "/etc/init.d/${myservice}") ]] ; then
			if [[ -z $(egrep 'svc_stop' "/etc/init.d/${myservice}") ]] || \
			   [[ -z $(egrep 'svc_start' "/etc/init.d/${myservice}") ]]
			then
				echo
				ewarn "Please use 'svc_stop; svc_start' and not 'stop; start' to"
				ewarn "restart the service in its custom 'restart()' function."
				ewarn "Run ${myservice} without arguments for more info."
				echo
				svc_restart
			else
				restart
			fi
		else
			restart
		fi

		# Restart dependencies as well
		if service_started "${myservice}" ; then
			for x in $(dolisting "${svcdir}/snapshot/$$/") ; do
				if service_stopped "${x##*/}" ; then
#					schedule_service_startup "${x##*/}"
					start_service "${x##*/}"
				fi
			done
		fi

		# Wait for any services that may still be running ...
#		[[ ${RC_PARALLEL_STARTUP} == "yes" ]] && wait

		rm -rf "${svcdir}/snapshot/$$"
		svcrestart="no"
		;;
	pause)
		svcpause="yes"
		svc_stop
		svcpause="no"
		;;
	--quiet|--nocolor)
		;;
	*)
		# Allow for homegrown functions
		svc_homegrown ${arg}
		;;
	esac
done


# vim:ts=4
