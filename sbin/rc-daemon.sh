# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# $Header$

[ -z "${svcdir}" ] && source /sbin/functions.sh

#stuff for getpids() and co
declare -ax MASTER_PID=""
declare -ax PID_LIST=""
DAEMONS=""
PID_FILES=""
RC_RETRY_KILL="no"
RC_RETRY_TIMEOUT=1
RC_RETRY_COUNT=5
RC_FAIL_ON_ZOMBIE="no"

# Override default settings with user settings ...
#[ -f /etc/conf.d/rc ] && source /etc/conf.d/rc

getpidfile() {
	local x=""
	local y=""
	local count=0
	local count2=0
	
	if [ "$#" -ne 1 -o -z "${DAEMONS}" ]
	then
		return 1
	else
		for x in ${DAEMONS}
		do
			if [ "${x}" != "$1" ]
			then
				count=$((count + 1))
				continue
			fi
			
			if [ -n "${PID_FILES}" ]
			then
				count2=0
				
				for y in ${PID_FILES}
				do
					if [ "${count}" -eq "${count2}" -a -f ${y} ]
					then
						echo "${y}"
						return 0
					fi
					
					count2=$((count2 + 1))
				done
				for y in ${PID_FILES}
				do
					if [ "$(eval echo \${y/${x}/})" != "${y}" -a -f ${y} ]
					then
						echo "${y}"
						return 0
					fi
				done
			else
				if [ -f /var/run/${x}.pid ]
				then
					echo "/var/run/${x}.pid"
					return 0
				elif [ -f /var/run/${myservice}/${x}.pid ]
				then
					echo "/var/run/${myservice}/${x}.pid"
					return 0
				fi
			fi
			
			count=$((count + 1))
		done
	fi
	
	return 1
}

#
# Simple funtion to return the pids of all the daemons in $DAEMONS
# in the array $PID_LIST, with the master pids in $MASTER_PID.
#
getpids() {
	local x=""
	local count=0
	local pidfile=""

	if [ -n "${DAEMONS}" ]
	then
		for x in ${DAEMONS}
		do
			MASTER_PID[${count}]=""
			PID_LIST[${count}]=""

			pidfile="$(getpidfile ${x})"
			if [ -n "${pidfile}" ]
			then
				MASTER_PID[${count}]="$(cat ${pidfile})"
			fi
			if [ -n "$(pidof ${x})" ]
			then
				PID_LIST[${count}]="$(pidof ${x})"
			fi
			
			count=$((count + 1))
		done
	fi

	return 0
}

#
# Return status:
#   0 - Everything looks ok, or rc-script do not start any daemons
#   1 - Master pid is dead, but other processes are running
#   2 - Master pid and all others (if any), are dead
#   3 - No pidfile, and no processes are running what so ever
#
checkpid() {
	local x=""
	local count=0

	if [ "$#" -ne 1 -o -z "$1" -o -z "${DAEMONS}" -o \
	     "$(eval echo \${DAEMONS/$1/})" = "${DAEMONS}" ]
	then
		return 3
	fi

	getpids

	for x in ${DAEMONS}
	do
		if [ "${x}" != "$1" ]
		then
			count=$((count + 1))
			continue
		fi

		if [ -z "${PID_LIST[${count}]}" -a -n "${MASTER_PID[${count}]}" ]
		then
			return 2
		elif [ -z "${PID_LIST[${count}]}" -a -z "${MASTER_PID[${count}]}" ]
		then
			return 3
		elif [ -n "${MASTER_PID[${count}]}" -a ! -d /proc/${MASTER_PID[${count}]} ]
		then
			return 1
		fi
		
		count=$((count + 1))
	done
	
	return 0
}

start-single-daemon() {
	local retval=0
	local pidfile=""
	local pidretval=0
	local daemon=""
	local SSD="start-stop-daemon"

	if [ "$(eval echo \${DAEMONS/$1/})" != "${DAEMONS}" ]
	then
		daemon="$1"
		shift

		# Just a stupid sanity check, need to improve here.
		# Basically we "check" that the daemon name is in
		# the args to SSD.
		if [ "$(eval echo \${*/${daemon}/})" = "$*" ]
		then
			return 1
		fi
	else
		return 1
	fi

	if [ -z "${DAEMONS}" -o "$#" -lt 1 -o -z "${daemon}" ]
	then
		return 1
	else
		${SSD} $*
		retval=$?

		if [ "${retval}" -ne 0 ]
		then
			return ${retval}
		fi

		checkpid ${daemon}
		pidretval=$?
		# Need to rethink checkpid return values, as we prob
		# need a switch or something that its ok, or not if
		# the master pid is dead, but some instances are running.
		if [ "${pidretval}" -ne 0 -a "${pidretval}" -ne 1 ]
		then
			return 1
		fi
	fi

	return ${retval}
}

#
# Stop a single daemon.  This is mainly used by stop-daemon().
# It takes the following arguments:
#
#    --kill-pidfile    If the pidfile exists, remove it.
#
#    --fail-zombie     If the process was not running, exit with
#                      a fail status.  Default is to exit cleanly.
#
stop-single-daemon() {
	local retval=0
	local pidfile=""
	local pidretval=0
	local killpidfile="no"
	local failonzombie="no"
	local daemon=""
	local SSD="start-stop-daemon --stop --quiet"

	for x in $*
	do
		case ${x} in
			--kill-pidfile)
				killpidfile="yes"
				;;
			--fail-zombie)
				failonzombie="yes"
				;;
			*)
				if [ "$(eval echo \${DAEMONS/${x}/})" != "${DAEMONS}" ]
				then
					if [ -n "${daemon}" ]
					then
						return 1
					fi
					
					daemon="${x}"
				fi
				;;
		esac
	done

	if [ -z "${DAEMONS}" -o "$#" -lt 1 -o -z "${daemon}" ]
	then
		return 1
	else
		checkpid ${daemon}
		pidretval=$?
		if [ "${pidretval}" -eq 0 ]
		then
			pidfile="$(getpidfile ${daemon})"
			if [ -n "${pidfile}" ]
			then
				${SSD} --pidfile ${pidfile}
				retval=$?
			else
				${SSD} --name ${daemon}
				retval=$?
			fi
		elif [ "${pidretval}" -eq 1 ]
		then
			${SSD} --name ${daemon}
			retval=$?
		elif [ "${pidretval}" -eq 2 ]
		then
			if [ "${RC_FAIL_ON_ZOMBIE}" = "yes" -o "${failonzombie}" = "yes" ]
			then
				retval=1
			fi
		elif [ "${pidretval}" -eq 3 ]
		then
			if [ "${RC_FAIL_ON_ZOMBIE}" = "yes" -o "${failonzombie}" = "yes" ]
			then
				retval=1
			fi
		fi
	fi

	#only delete the pidfile if the daemon is dead
	if [ "${killpidfile}" = "yes" ]
	then
		checkpid ${daemon}
		pidretval=$?
		if [ "${pidretval}" -eq 2 -o "${pidretval}" -eq 3 ]
		then
			rm -f $(getpidfile ${x})
		fi
	fi

	#final sanity check
	if [ "${retval}" -eq 0 ]
	then
		checkpid ${daemon}
		pidretval=$?
		if [ "${pidretval}" -eq 0 -o "${pidretval}" -eq 1 ]
		then
			retval=$((retval + 1))
		fi
	fi
	
	return ${retval}
}

#
# Should be used to stop daemons in rc-scripts.  It will
# stop all the daemons in $DAEMONS.  The following arguments
# are supported:
#
#    --kill-pidfile    Remove the pidfile if it exists (after
#                      daemon is stopped)
#
#    --fail-zombie     If the process is not running, exit with
#                      a fail status (default is to exit cleanly).
#
#    --retry           If not sucessfull, retry the number of times
#                      as specified by $RC_RETRY_COUNT
#
stop-daemons() {
	local x=""
	local count=0
	local retval=0
	local tmpretval=0
	local pidretval=0
	local retry="no"
	local ssdargs=""

	if [ -z "${DAEMONS}" ]
	then
		return 0
	fi

	for x in $*
	do
		case ${x} in
			--kill-pidfile)
				ssdargs="${ssdargs} --kill-pidfile"
				;;
			--fail-zombie)
				ssdargs="${ssdargs} --fail-zombie"
				;;
			--retry)
				retry="yes"
				;;
			*)
				eerror "  ERROR: invalid argument to stop-daemon()!"
				return 1
				;;
		esac
	done

	if [ "${retry}" = "yes" -o "${RC_RETRY_KILL}" = "yes" ]
	then
		for x in ${DAEMONS}
		do
			count=0
			pidretval=0
		
			while ([ "${pidretval}" -eq 0 -o "${pidretval}" -eq 1 ]) && \
				  [ "${count}" -lt "${RC_RETRY_COUNT}" ]
			do
				if [ "${count}" -ne 0 -a -n "${RC_RETRY_TIMEOUT}" ]
				then
					sleep ${RC_RETRY_TIMEOUT}
				fi

				stop-single-daemon ${ssdargs} ${x}
				tmpretval=$?

				checkpid ${x}
				pidretval=$?

				count=$((count + 1))
			done
			
			retval=$((retval + tmpretval))
		done
	else
		for x in ${DAEMONS}
		do
			stop-single-daemon ${ssdargs} ${x}
			retval=$((retval + $?))
		done
	fi

	return ${retval}
}


# vim:ts=4
