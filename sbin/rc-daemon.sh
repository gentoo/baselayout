# Copyright 1999-2005 Gentoo Foundation 
# Distributed under the terms of the GNU General Public License v2
# $Header$

# RC functions to work with daemons
# Basically we're a fancy wrapper for start-stop-daemon
# and should be called as such. This means that our init scripts
# should work as is with zero modification :)

RC_GOT_DAEMON="yes"

[[ ${RC_GOT_FUNCTIONS} != "yes" ]] && source /sbin/functions.sh

RC_RETRY_KILL="no"
RC_RETRY_TIMEOUT=1
RC_RETRY_COUNT=5
RC_FAIL_ON_ZOMBIE="no"
RC_KILL_CHILDREN="no"
RC_WAIT_ON_START="0.1"

# Override default settings with user settings ...
[[ -f /etc/conf.d/rc ]] && source /etc/conf.d/rc

# void setup_daemon_vars(void)
#
# Setup our vars based on the start-stop-daemon command
setup_daemon_vars() {
	local name
	local -a sargs=( "${args%% -- *}" )
	exeargs="-- ${args##* -- }"

	local i j=${#sargs[@]}
	for (( i=0; i<j; i++ )); do
		case ${sargs[i]} in
			-S|--start)
				stopping=false
				unset sargs[i]
				;;
			-K|--stop)
				stopping=true
				unset sargs[i]
				;;
			-n|--name)
				[[ ${i} -lt ${j} ]] && name=${sargs[i+1]}
				;;
			-x|--exec|-a|--startas)
				[[ ${i} -lt ${j} ]] && cmd=${sargs[i+1]}
				;;
			-p|--pidfile)
				[[ ${i} -lt ${j} ]] && pidfile=${sargs[i+1]}
				;;
			--pid=*)
				pidfile=${sargs[i]##--pid=}
				;;
			-s|--signal)
				[[ ${i} -lt ${j} ]] && signal=${sargs[i+1]}
				;;
			-t|--test|-o|--oknodo)
				nothing=true
				;;
		esac
	done

	ssdargs="${sargs[@]}"
	[[ -z ${cmd} ]] && cmd=${name}
}

# bool try_kill_pid(int pid, char* signal, bool session)
#
# Repeatedly kill the pid with the given signal until it dies
# If session is true then we use tread pid as session and send it
# via pkill
# Returns 0 if successfuly otherwise 1
try_kill_pid() {
	local pid=$1 signal=${2:-TERM} session=${3:-false}  i s
	
	# We split RC_RETRY_TIMEOUT into tenths of seconds
	# So we return as fast as possible
	(( s=${RC_RETRY_TIMEOUT}/10 ))

	for (( i=0; i<RC_RETRY_COUNT*10; i++ )); do
		if ${session} ; then
			if [[ -x /usr/bin/pkill ]]; then
				/usr/bin/pkill -${signal} -s ${pid} || return 0
			else
				local pids=$( /bin/ps -eo pid,sid | /bin/sed -n 's/'${pid}'$//p' )
				[[ -z ${pids} ]] && return 0
				/bin/kill -s ${signal} ${pids} 2>/dev/null
			fi
		else
			/bin/kill -s ${signal} ${pid} 2>/dev/null || return 0
		fi
		LC_ALL=C /bin/sleep ${s}
	done

	return 1
}

# bool kill_pid(int pid, bool session)
#
# Kills the given pid/session
# Returns 1 if we fail to kill the pid (if it's valid) otherwise 0
kill_pid() {
	local pid=$1 session=${2:-false}

	try_kill_pid ${pid} ${signal} ${session} && return 0

	[[ ${RC_RETRY_KILL} == "yes" ]] \
		&& try_kill_pid ${pid} KILL ${session} && return 0

	return 1 
}

# bool is_daemon_running(char* cmd, char* pidfile)
#
# Returns 0 if the given daemon is running, otherwise 1
# If a pidfile is supplied, the pid inside it must match
# a pid in the list of pidof ${cmd}
is_daemon_running() {
	local exe=$1 pidfile=$2 pids pid
	
	pids=$( /bin/pidof ${exe} )
	[[ -z ${pids} ]] && return 1
	
	if [[ -s ${pidfile} ]]; then
		read pid < ${pidfile}
		if [[ -n ${pid} ]]; then
			[[ *" ${pid} "* == " ${pids} " ]]
			return $?
		fi
	fi
	return 0
}

# int start_daemon(void)
#
# We don't do anyting fancy - just pass the given options
# to start-stop-daemon and return the value
start_daemon() {
	local retval
	
	eval /sbin/start-stop-daemon "${args}"
	retval=$?

	[[ ${retval} != 0 ]] && return ${retval}
	[[ ${RC_WAIT_ON_START} == 0 ]] && return ${retval}

	# We pause for RC_WAIT_ON_START seconds and then
	# check if the daemon is still running - this is mainly
	# to handle daemons who launch and then fail due to invalid
	# configuration files
	LC_ALL=C /bin/sleep ${RC_WAIT_ON_START}
	is_daemon_running ${cmd} ${pidfile}
	retval=$?
	[[ ${retval} == 0 ]] && return 0
	
	# Stop if we can to clean things up
	if [[ $( type -t stop ) == "function" ]]; then
		stop >/dev/null # We don't want to echo ebegin/eend
	elif [[ -n ${pidfile} ]]; then
		stop_daemon
	fi
	return ${retval}
}

# bool stop_daemon(void)
#
# Instead of calling start-stop-daemon we instead try and
# kill the process ourselves and any children left over
# Returns 0 if everything was successful otherwise 1
stop_daemon() {
	local pid pids retval=0

	if [[ -n ${cmd} ]]; then
		if ! is_daemon_running ${cmd} ${pidfile} ; then
			[[ ${RC_FAIL_ON_ZOMBIE} == "yes" ]] && return 1
		fi
		pids=$( /bin/pidof ${cmd} )
	fi

	if [[ -s ${pidfile} ]]; then
		read pid < ${pidfile}
		# Check that the given program is actually running the pid
		[[ -n ${pids} && " ${pids} " != *" ${pid} "* ]] && return 1
		pids=${pid}
	fi

	for pid in ${pids}; do
		if [[ ${RC_FAIL_ON_ZOMBIE} == "yes" ]]; then
			/bin/ps -p ${pid} &>/dev/null || return 1
		fi

		if kill_pid ${pid} false ; then
			# Remove the pidfile if the process didn't
			[[ -f ${pidfile} ]] && /bin/rm -f ${pidfile}
		else
			retval=1
		fi

		if [[ ${RC_KILL_CHILDREN} == "yes" ]]; then
			kill_pid ${pid} true || retval=1
		fi
	done
	
	return ${retval}
}

# int start-stop-daemon(...)
#
# Provide a wrapper to start-stop-daemon
# Return the result of start_daemon or stop_daemon depending on
# how we are called
start-stop-daemon() {
	local args=$( requote "$@" ) ssdargs exeargs x
	local cmd pidfile pid stopping nothing=false signal=TERM

	setup_daemon_vars

	# We pass --oknodo and --test directly to start-stop-daemon and return
	if ${nothing}; then
		eval /sbin/start-stop-daemon "${args}"
		return $?
	fi

	if ${stopping}; then
		stop_daemon 
	else
		start_daemon
	fi
	return $?
}

# vim:ts=4
