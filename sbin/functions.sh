# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License, v2 or later
# $Header$

#setup a basic $PATH
[ -z "${PATH}" ] && PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/sbin"

#daemontools dir
SVCDIR="/var/lib/supervise"

#rc-scripts dir
svcdir="/mnt/.init.d"

svcfstype="tmpfs"

#size of $svcdir in KB
svcsize=1024

#different types of dependancies
deptypes="need use"

#different types of order deps
ordtypes="before after"

#
# Internal variables
#

#dont output to stdout?
QUIET_STDOUT="no"

#stuff for getpids() and co
declare -ax MASTERPID=""
declare -ax PIDLIST=""
DAEMON=""
PIDFILE=""
RCRETRYKILL="no"
RCRETRYTIMEOUT=1
RCRETRYCOUNT=5
RCFAILONZOMBIE="no"

[ -f /etc/conf.d/rc ] && source /etc/conf.d/rc


getcols() {
	echo "${2}"
}

COLS="$(stty size 2>/dev/null)"
COLS="$(getcols $COLS)"
COLS=$((${COLS} -7))
ENDCOL=$'\e[A\e['${COLS}'G'
#now, ${ENDCOL} will move us to the end of the column;
#irregardless of character width

NORMAL="\033[0m"
GOOD=$'\e[32;01m'
WARN=$'\e[33;01m'
BAD=$'\e[31;01m'
NORMAL=$'\e[0m'

HILITE=$'\e[36;01m'

esyslog() {
	if [ -x /usr/bin/logger ]
	then
		pri="${1}"
		tag="${2}"
		shift 2
		/usr/bin/logger -p ${pri} -t ${tag} -- $*
	fi
}

ebegin() {
	if [ "${QUIET_STDOUT}" = "yes" ]
	then
		return
	else
		echo -e " ${GOOD}*${NORMAL} ${*}..."
	fi
}

ewarn() {
	if [ "${QUIET_STDOUT}" = "yes" ]
	then
		echo " ${*}"
	else
		echo -e " ${WARN}*${NORMAL} ${*}"
	fi

	# Log warnings to system log
	esyslog "daemon.warning" "rc-scripts" "${*}"
}

eerror() {
	if [ "${QUIET_STDOUT}" = "yes" ]
	then
		echo " ${*}" >/dev/stderr
	else
		echo -e " ${BAD}*${NORMAL} ${*}"
	fi

	# Log errors to system log
	esyslog "daemon.err" "rc-scripts" "${*}"
}

einfo() {
	if [ "${QUIET_STDOUT}" = "yes" ]
	then
		return
	else
		echo -e " ${GOOD}*${NORMAL} ${*}"
	fi
}

einfon() {
	if [ "${QUIET_STDOUT}" = "yes" ]
	then
		return
	else
		echo -ne " ${GOOD}*${NORMAL} ${*}"
	fi
}

# void eend(int error, char *errstr)
#
eend() {
	if [ "$#" -eq 0 ] || [ "${1}" -eq 0 ]
	then
		if [ "${QUIET_STDOUT}" != "yes" ]
		then
			echo -e "${ENDCOL}  \e[34;01m[ ${GOOD}ok \e[34;01m]${NORMAL}"
		fi
	else
		local returnme="${1}"
		shift
		if [ "$#" -ge 1 ]
		then
			eerror "${*}"
		fi
		if [ "${QUIET_STDOUT}" != "yes" ]
		then
			echo -e "${ENDCOL}  \e[34;01m[ ${BAD}!! \e[34;01m]${NORMAL}"
			#extra spacing makes it easier to read
			if [ "$#" -ge 1 ]
			then
				echo
			fi
		fi
		return ${returnme}
	fi
}

# void ewend(int error, char *errstr)
#
ewend() {
	if [ "$#" -eq 0 ] || [ "${1}" -eq 0 ]
	then
		if [ "${QUIET_STDOUT}" != "yes" ]
		then
			echo -e "${ENDCOL}  \e[34;01m[ ${GOOD}ok \e[34;01m]${NORMAL}"
		fi
	else
		local returnme="${1}"
		if [ "$#" -ge 2 ]
		then
			shift
			ewarn "${*}"
		fi
		if [ "${QUIET_STDOUT}" != "yes" ]
		then
			echo -e "${ENDCOL}  \e[34;01m[ ${WARN}!! \e[34;01m]${NORMAL}"
			#extra spacing makes it easier to read
			echo
		fi
		return ${returnme}
	fi
}

# bool wrap_rcscript(full_path_and_name_of_rc-script)
#
#   return 0 if the script have no syntax errors in it
#
wrap_rcscript() {
	local retval=1

	( echo "function test_script() {" ; cat ${1}; echo "}" ) > ${svcdir}/foo.sh

	if source ${svcdir}/foo.sh &>/dev/null
	then
		test_script &>/dev/null
		retval=0
	fi
	rm -f ${svcdir}/foo.sh
	return ${retval}
}

getpidfile() {
	local x=""
	local y=""
	local count=0
	local count2=0
	
	if [ "$#" -ne 1 ] || [ -z "${DAEMON}" ]
	then
		return 1
	else
		for x in ${DAEMON}
		do
			if [ "${x}" != "${1}" ]
			then
				count=$(($count + 1))
				continue
			fi
			
			if [ -n "${PIDFILE}" ]
			then
				count2=0
				
				for y in ${PIDFILE}
				do
					if [ "${count}" -eq "${count2}" ] && [ -f ${y} ]
					then
						echo "${y}"
						return 0
					fi
					
					count2=$((${count2} + 1))
				done
				for y in ${PIDFILE}
				do
					if [ "$(eval echo \${y/${x}/})" != "${y}" ] && [ -f ${y} ]
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
			
			count=$((${count} + 1))
		done
	fi
	
	return 1
}

#
# Simple funtion to return the pids of all the daemons in $DAEMON
# in the array $PIDLIST, with the master pids in $MASTERPID.
#
getpids() {
	local x=""
	local count=0
	local pidfile=""

	if [ -n "${DAEMON}" ]
	then
		for x in ${DAEMON}
		do
			MASTERPID[${count}]=""
			PIDLIST[${count}]=""

			pidfile="$(getpidfile ${x})"
			if [ -n "${pidfile}" ]
			then
				MASTERPID[${count}]="$(cat ${pidfile})"
			fi
			if [ -n "$(pidof ${x})" ]
			then
				PIDLIST[${count}]="$(pidof ${x})"
			fi
			
			count=$((${count} + 1))
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

	if [ "$#" -ne 1 ] || [ -z "${1}" ] || [ -z "${DAEMON}" ] || \
	   [ "$(eval echo \${DAEMON/${1}/})" == "${DAEMON}" ]
	then
		return 3
	fi

	getpids

	for x in ${DAEMON}
	do
		if [ "${x}" != "${1}" ]
		then
			count=$((${count} + 1))
			continue
		fi

		if [ -z "${PIDLIST[${count}]}" ] && \
		   [ -n "${MASTERPID[${count}]}" ]
		then
			return 2
		elif [ -z "${PIDLIST[${count}]}" ] && \
		     [ -z "${MASTERPID[${count}]}" ]
		then
			return 3
		elif [ -n "${MASTERPID[${count}]}" ] && \
		     [ ! -d /proc/${MASTERPID[${count}]} ]
		then
			return 1
		fi
		
		count=$((${count} + 1))
	done
	
	return 0
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
				if [ "$(eval echo \${DAEMON/${x}/})" != "${DAEMON}" ]
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

	if [ -z "${DAEMON}" ] || [ "$#" -lt 1 ] || [ -z "${daemon}" ]
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
			if [ "${RCFAILONZOMBIE}" = "yes" ] || [ "${failonzombie}" = "yes" ]
			then
				retval=1
			fi
		elif [ "${pidretval}" -eq 3 ]
		then
			if [ "${RCFAILONZOMBIE}" = "yes" ] || [ "${failonzombie}" = "yes" ]
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
		if [ "${pidretval}" -eq 2 ] || [ "${pidretval}" -eq 3 ]
		then
			rm -f $(getpidfile ${x})
		fi
	fi

	#final sanity check
	if [ "${retval}" -eq 0 ]
	then
		checkpid ${daemon}
		pidretval=$?
		if [ "${pidretval}" -eq 0 ] || [ "${pidretval}" -eq 1 ]
		then
			retval=$((${retval} + 1))
		fi
	fi
	
	return ${retval}
}

#
# Should be used to stop daemons in rc-scripts.  It will
# stop all the daemons in $DAEMON.  The following arguments
# are supported:
#
#    --kill-pidfile    Remove the pidfile if it exists (after
#                      daemon is stopped)
#
#    --fail-zombie     If the process is not running, exit with
#                      a fail status (default is to exit cleanly).
#
#    --retry           If not sucessfull, retry the number of times
#                      as specified by $RCRETRYCOUNT
#
stop-daemon() {
	local x=""
	local count=0
	local retval=0
	local tmpretval=0
	local pidretval=0
	local retry="no"
	local ssdargs=""

	if [ -z "${DAEMON}" ]
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

	if [ "${retry}" = "yes" ] || [ "${RCRETRYKILL}" = "yes" ]
	then
		for x in ${DAEMON}
		do
			count=0
			pidretval=0
		
			while ([ "${pidretval}" -eq 0 ] || \
			       [ "${pidretval}" -eq 1 ]) && \
				  [ "${count}" -lt "${RCRETRYCOUNT}" ]
			do
				if [ "${count}" -ne 0 ] && [ -n "${RCRETRYTIMEOUT}" ]
				then
					sleep ${RCRETRYTIMEOUT}
				fi

				stop-single-daemon ${ssdargs} ${x}
				tmpretval=$?

				checkpid ${x}
				pidretval=$?

				count=$((${count} + 1))
			done
			
			retval=$((${retval} + ${tmpretval}))
		done
	else
		for x in ${DAEMON}
		do
			stop-single-daemon ${ssdargs} ${x}
			retval=$((${retval} + $?))
		done
	fi

	return ${retval}
}

# bool get_bootparam(param)
#
#   return 0 if gentoo=param was passed to the kernel
#
#   NOTE: you should always query the longer argument, for instance
#         if you have 'nodevfs' and 'devfs', query 'nodevfs', or 
#         results may be unpredictable.
#
#         if get_bootparam "nodevfs" -eq 0 ; then ....
#
get_bootparam() {
	local copt=""
	local parms=""
	local retval=1
	for copt in $(cat /proc/cmdline)
	do
		if [ "${copt%=*}" = "gentoo" ]
		then
			parms="${copt##*=}"
			#parse gentoo option
			if [ "$(eval echo \${parms/${1}/})" != "${parms}" ]
			then
				retval=0
			fi
		fi
	done
	return ${retval}
}

# Safer way to list the contents of a directory,
# as it do not have the "empty dir bug".
#
# char *dolisting(param)
#
#   print a list of the directory contents
#
#   NOTE: quote the params if they contain globs.
#         also, error checking is not that extensive ...
#
dolisting() {
	local x=""
	local y=""
	local tmpstr=""
	local mylist=""
	local mypath="${*}"

	if [ "${mypath%/\*}" != "${mypath}" ]
	then
		mypath="${mypath%/\*}"
	fi
	for x in ${mypath}
	do
		if [ ! -e ${x} ]
		then
			continue
		fi
		if [ ! -d ${x} ] && ( [ -L ${x} ] || [ -f ${x} ] )
		then
			mylist="${mylist} $(ls ${x} 2>/dev/null)"
		else
			if [ "${x%/}" != "${x}" ]
			then
				x="${x%/}"
			fi
			cd ${x}
			tmpstr="$(ls)"
			for y in ${tmpstr}
			do
				mylist="${mylist} ${x}/${y}"
			done
		fi
	done
	echo "${mylist}"
}

# void save_options(char *option, char *optstring)
#
#   save the settings ("optstring") for "option"
#
save_options() {
	local myopts="${1}"
	shift
	if [ ! -d ${svcdir}/options/${myservice} ]
	then
		install -d -m0755 ${svcdir}/options/${myservice}
	fi
	echo "${*}" > ${svcdir}/options/${myservice}/${myopts}
}

# char *get_options(char *option)
#
#   get the "optstring" for "option" that was saved
#   by calling the save_options function
#
get_options() {
	if [ -f ${svcdir}/options/${myservice}/${1} ]
	then
		cat ${svcdir}/options/${myservice}/${1}
	fi
}


# vim:ts=4
