# Copyright 1999-2005 Gentoo Foundation 
# Distributed under the terms of the GNU General Public License v2
# $Header$

# RC functions to work with daemons
# Basically we're a fancy wrapper for start-stop-daemon
# and should be called as such. This means that our init scripts
# should work as is with zero modification :)

# We rely on the /proc filesystem a lot here to save shelling out
# to userspace tools. This makes us quite fast but less portable I guess.

RC_GOT_DAEMON="yes"

[[ ${RC_GOT_FUNCTIONS} != "yes" ]] && source /sbin/functions.sh

RC_RETRY_KILL="no"
RC_RETRY_TIMEOUT=1
RC_RETRY_COUNT=5
RC_FAIL_ON_ZOMBIE="no"
RC_KILL_CHILDREN="no"

# Override default settings with user settings ...
[[ -f /etc/conf.d/rc ]] && source /etc/conf.d/rc

# void setup_daemon_vars(void)
#
# Setup our vars based on the start-stop-daemon command
setup_daemon_vars() {
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
			-x|--exec)
				[[ ${i} -lt ${j} ]] && exe=${sargs[i+1]}
				;;
			-p|--pidfile)
				[[ ${i} -lt ${j} ]] && pidfile=${sargs[i+1]}
				;;
			--pid=*)
				pidfile=${sargs[i]##--pid=}
				;;
			-t|--test|-o|--oknodo)
				nothing=true
				;;
		esac
	done

	ssdargs="${sargs[@]}"
}

# bool try_kill_pid(int pid, int sig)
#
# Repeatedly kill the pid with the given signal until it dies
# Returns 0 if successfuly otherwise 1
try_kill_pid() {
	local pid=$1 sig=${2:-TERM} i s
	
	# We split RC_RETRY_TIMEOUT into tenths of seconds
	# So we return as fast as possible
	(( s=${RC_RETRY_TIMEOUT}/10 ))
	
	for (( i=0; i<RC_RETRY_COUNT*10; i++ )); do
		[[ ! -d /proc/${pid} ]] && return 0
		kill -s ${sig} ${pid}
		LC_ALL=C sleep ${s}
	done

	return 1
}

# bool kill_pid(int pid, int ppid)
#
# Kills the given pid
# If a parent pid (ppid) is supplied, the pid has to be a child of ppid
# Returns 1 if we fail to kill the pid (if it's valid) otherwise 0
kill_pid() {
	local pid=$1 ppid=$2 i
	local a b c d e f g

	# Check that our pid really exists
	[[ ! -d /proc/${pid} ]] && return 0

	# If supplied a ppid (parent pid) then check that it still a child
	# of the pid still. If not, return 0 as we haven't failed to kill
	# as it's not a valid child
	if [[ -n ${ppid} ]]; then
		read a b c d e f g < /proc/${pid}/stat
		[[ ${ppid} != ${e} ]] && return 0
	fi

	# Now we kill the pid
	try_kill_pid ${pid} TERM && return 0

	# Naughty pid - it didn't die nicely.
	# Should we just KILL it?
	[[ ${RC_RETRY_KILL} == "yes" ]] \
		&& try_kill_pid ${pid} KILL && return 0
	
	# We failed to kill the pid :(
	# But do a quick test to see if it's alive or not
	[[ ! -d /proc/${pid} ]]
	return $?
}

# bool kill_children(int ppid)
#
# Stops all children of the given pid
# Returns 1 if any fail to stop otherwise 0
kill_children() {
	local ppid=$1 pid retval=0
	local children=$( pgrep -s ${ppid} )

	for pid in "${children}"; do
		kill_pid ${pid} ${ppid} || retval=1
	done

	return ${retval}
}

# int start_daemon(void)
#
# We don't do anyting fancy - just pass the given options
# to start-stop-daemon and return the value
start_daemon() {
	/sbin/start-stop-daemon ${args}
	return $?
}

# bool stop_daemon(void)
#
# Instead of calling start-stop-daemon we instead try and
# kill the process ourselves and any children left over
# Returns 0 if everything was successful otherwise 1
stop_daemon() {
	local pids retval=0
	
	if [[ -s ${pidfile} ]]; then
		pids=$( < ${pidfile} )
	elif [[ -n ${exe} ]]; then
		pids=$( pidof ${exe} )
	elif [[ -n ${name} ]]; then
		pids=$( pidof ${name} )
	else
		# We are given nothing to stop, so fail
		return 1
	fi

	for pid in "${pids}"; do
		if [[ ${RC_FAIL_ON_ZOMBIE} == "yes" ]]; then
			[[ ! -d /proc/${pid} ]] && return 1
		fi

		if kill_pid ${pid} ; then
			# Remove the pidfile if the process didn't
			[[ -f ${pidfile} ]] && rm -f ${pidfile}
		else
			retval=1
		fi
	
		if [[ ${RC_KILL_CHILDREN} == "yes" ]]; then
			kill_children ${pid} || retval=1
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
	local args=" $* " ssdargs exeargs
	local exe name pidfile pid stopping nothing=false
	setup_daemon_vars

	# We pass --oknodo and --test directly to start-stop-daemon and return
	if ${nothing}; then
		/sbin/start-stop-daemon ${args}
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
