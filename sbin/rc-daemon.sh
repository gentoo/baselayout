# Copyright 1999-2006 Gentoo Foundation 
# Distributed under the terms of the GNU General Public License v2

# RC functions to work with daemons
# Basically we're a fancy wrapper for start-stop-daemon
# and should be called as such. This means that our init scripts
# should work as is with zero modification :)

# Actually, the above is a small as lie we have some init scripts which try to
# get start-stop-daemon to launch a shell script. While this does work with
# the start-stop-daemon program in /sbin, it does cause a problem for us
# when we're testing for the daemon to be running. I (Roy Marples) view this
# as behaviour by design as start-stop-daemon should not be used to run shell
# scripts!

RC_GOT_DAEMON="yes"

[[ ${RC_GOT_FUNCTIONS} != "yes" ]] && source /sbin/functions.sh
[[ ${RC_GOT_SERVICES} != "yes" ]] && source "${svclib}/sh/rc-services.sh"

RC_RETRY_KILL="no"
RC_RETRY_TIMEOUT=1
RC_RETRY_COUNT=5
RC_FAIL_ON_ZOMBIE="no"
RC_KILL_CHILDREN="no"
RC_WAIT_ON_START="0.1"

# void rc_shift_args(void)
#
# Proccess vars - makes things easier by using the shift command
# and indirect variables
rc_shift_args() {
	local addvar
	
	while [[ $# != "0" ]]; do
		if [[ $1 != "-"* && -n ${addvar} ]]; then
			if [[ -z ${!addvar} ]]; then
				eval "${addvar}=\"$1\""
			else
				eval "${addvar}=\"${!addvar} $1\""
			fi
			shift
			continue
		fi
		unset addvar
		case "$1" in
			-S|--start)
				stopping=false
				;;
			-K|--stop)
				stopping=true
				;;
			-n|--name)
				addvar="name"
				;;
			-x|--exec|-a|--startas)
				addvar="cmd"
				;;
			-p|--pidfile)
				addvar="pidfile"
				;;
			--pidfile=*)
				pidfile="${1##--pidfile=}"
				;;
			--pid=*)
				pidfile="${1##--pid=}"
				;;
			-R|--retry)
				unset RC_RETRY_COUNT
				addvar="RC_RETRY_COUNT"
				;;
			-s|--signal)
				addvar="signal"
				;;
			-t|--test|-o|--oknodo)
				nothing=true
				;;
		esac
		shift
	done

	[[ -z ${RC_RETRY_COUNT} ]] && RC_RETRY_COUNT=5
}	

# void rc_setup_daemon_vars(void)
#
# Setup our vars based on the start-stop-daemon command
rc_setup_daemon_vars() {
	local name i
	local -a sargs=( "${args%% \'--\' *}" )
	local -a eargs
	local x="${args// \'--\' /}"
	[[ ${x} != "${args}" ]] && eargs=( "${args##* \'--\' }" )

	eval rc_shift_args "${sargs[@]}"

	[[ -z ${cmd} ]] && cmd="${name}"

	# We may want to launch the daemon with a custom command
	# This is mainly useful for debugging with apps like valgrind, strace
	local bash_service="$( bash_variable "${SVCNAME}" )"
	if [[ -n ${RC_DAEMON} ]]; then
		local -a d=( ${RC_DAEMON} )
		if ${stopping}; then
			args="--stop"
		else
			args="--start"
		fi

		# Add -- or - arguments as s-s-d options
		j=${#d[@]}
		for (( i=0; i<j; i++ )); do
			[[ ${d[i]:0:1} != "-" ]] && break
			args="${args} ${d[i]}"
			unset d[i]
		done
		d=( "${d[@]}" )

		eval args=\"${args} --exec '${d[0]}' -- ${d[@]:1} '${cmd}' ${eargs[@]}\"
		! ${stopping} && cmd="${d[0]}"
	fi

	return 0
}

# bool rc_try_kill_pid(int pid, char* signal, bool session)
#
# Repeatedly kill the pid with the given signal until it dies
# If session is true then we use tread pid as session and send it
# via pkill
# Returns 0 if successfuly otherwise 1
rc_try_kill_pid() {
	local pid="$1" signal="${2:-TERM}" session="${3:-false}" i s p e

	# We split RC_RETRY_TIMEOUT into tenths of seconds
	# So we return as fast as possible
	s=$(( ${RC_RETRY_TIMEOUT}/10 )).$(( ${RC_RETRY_TIMEOUT}%10 ))

	for (( i=0; i<RC_RETRY_COUNT*10; i++ )); do
		if ${session} ; then
			if [[ -x /usr/bin/pkill ]]; then
				pkill "-${signal}" -s "${pid}"
				pgrep -s "${pid}" >/dev/null || return 0
			else
				local pids="$(ps eo pid,sid | sed -n "s/ ${pid}\$//p")"
				[[ -z ${pids} ]] && return 0
				kill -s "${signal}" ${pids} 2>/dev/null
				e=false
				for p in ${pids}; do
					if [[ -d "/proc/${p}" ]]; then
						e=true
						break
					fi
				done
				${e} || return 0
			fi
		else
			kill -s "${signal}" "${pid}" 2>/dev/null
			[[ ! -d "/proc/${pid}" ]] && return 0
		fi
		LC_ALL=C /bin/sleep "${s}"
	done

	return 1
}

# bool rc_kill_pid(int pid, bool session)
#
# Kills the given pid/session
# Returns 1 if we fail to kill the pid (if it's valid) otherwise 0
rc_kill_pid() {
	local pid="$1" session="${2:-false}"

	rc_try_kill_pid "${pid}" "${signal}" "${session}" && return 0

	[[ ${RC_RETRY_KILL} == "yes" ]] \
		&& rc_try_kill_pid "${pid}" KILL "${session}" && return 0

	return 1 
}

# char* pidof(char* cmd, ...)
#
# Returns a space seperated list of pids associated with the command
# This is to handle the rpc.nfsd program which acts weird
pidof() {
	local arg args 

	for arg in "$@"; do
		[[ ${arg##*/} == "rpc.nfsd" ]] && arg="${arg%/*}/nfsd"
		args="${args} '"${arg}"'"
	done

	eval /bin/pidof -x ${args}
}

# bool is_daemon_running(char* cmd, char* pidfile)
#
# Returns 0 if the given daemon is running, otherwise 1
# If a pidfile is supplied, the pid inside it must match
# a pid in the list of pidof ${cmd}
is_daemon_running() {
	local cmd pidfile pids pid

	if [[ $# == "1" ]]; then
		cmd="$1"
	else
		local i j="$#"
		for (( i=0; i<j-1; i++ )); do
			cmd="${cmd} $1"
			shift
		done
		pidfile="$1"
	fi

	pids="$( pidof ${cmd} )"
	[[ -z ${pids} ]] && return 1

	[[ -s ${pidfile} ]] || return 0

	read pid < "${pidfile}"
	pids=" ${pids} "
	[[ ${pids// ${pid} /} != "${pids}" ]]
}

# int rc_start_daemon(void)
#
# We don't do anyting fancy - just pass the given options
# to start-stop-daemon and return the value
rc_start_daemon() {
	eval /sbin/start-stop-daemon "${args}"
	local retval="$?"

	[[ ${retval} != "0" ]] && return "${retval}"
	[[ ${RC_WAIT_ON_START} == "0" ]] && return "${retval}"

	# Give the daemon upto 1 second to fork after s-s-d returns
	# Some daemons like acpid and vsftpd need this when system is under load
	# Seems to be only daemons that do not create pid files though ...
	local i=0
	for ((i=0; i<10; i++)); do
		is_daemon_running ${cmd} "${pidfile}" && break
		LC_ALL=C /bin/sleep "0.1"
	done

	# We pause for RC_WAIT_ON_START seconds and then
	# check if the daemon is still running - this is mainly
	# to handle daemons who launch and then fail due to invalid
	# configuration files
	LC_ALL=C /bin/sleep "${RC_WAIT_ON_START}"
	is_daemon_running ${cmd} "${pidfile}"
	retval="$?"
	[[ ${retval} == "0" ]] && return 0

	# Stop if we can to clean things up
	[[ -n ${pidfile} ]] && rc_stop_daemon

	return "${retval}"
}

# bool rc_stop_daemon(void)
#
# Instead of calling start-stop-daemon we instead try and
# kill the process ourselves and any children left over
# Returns 0 if everything was successful otherwise 1
rc_stop_daemon() {
	local pid pids retval="0"

	if [[ -n ${cmd} ]]; then
		if ! is_daemon_running ${cmd} "${pidfile}" ; then
			[[ ${RC_FAIL_ON_ZOMBIE} == "yes" ]] && return 1
		fi
		pids="$( pidof ${cmd} )"
	fi

	if [[ -s ${pidfile} ]]; then
		read pid < "${pidfile}"
		# Check that the given program is actually running the pid
		if [[ -n ${pids} ]]; then
			pids=" ${pids} "
			[[ ${pids// ${pid} /} == "${pids}" ]] && return 1
		fi
		pids="${pid}"
	fi

	# If there's nothing to kill then return without error
	[[ -z ${pids} ]] && return 0

	# We may not have pgrep to find our children, so we provide
	# two methods
	if [[ ${RC_KILL_CHILDREN} == "yes" ]]; then
		if [[ -x /usr/bin/pgrep ]]; then
			pids="${pids} $(pgrep -P "${pids// /,}")"
		else
			local npids
			for pid in ${pids} ; do
				npids="${npids} $(ps eo pid,ppid | sed -n "s/ ${pid}\$//p")"
			done
			pids="${pids} ${npids}"
		fi
	fi

	for pid in ${pids}; do
		if [[ ${RC_FAIL_ON_ZOMBIE} == "yes" ]]; then
			ps p "${pid}" &>/dev/null || return 1
		fi

		if rc_kill_pid "${pid}" false ; then
			# Remove the pidfile if the process didn't
			[[ -f ${pidfile} ]] && rm -f "${pidfile}"
		else
			retval=1
		fi

		if [[ ${RC_KILL_CHILDREN} == "yes" ]]; then
			rc_kill_pid "${pid}" true || retval=1
		fi
	done

	return "${retval}"
}

# void update_service_status(char *service)
#
# Loads the service state file and ensures that all listed daemons are still
# running - hopefully on their correct pids too
# If not, we stop the service
update_service_status() {
	local service="$1" daemonfile="${svcdir}/daemons/$1" i
	local -a RC_DAEMONS=() RC_PIDFILES=()

	# We only care about marking started services as stopped if the daemon(s)
	# for it are no longer running
	! service_started "${service}" && return
	[[ ! -f ${daemonfile} ]] && return

	# OK, now check that every daemon launched is active
	# If the --start command was any good a pidfile was specified too
	source "${daemonfile}"
	for (( i=0; i<${#RC_DAEMONS[@]}; i++ )); do
		if ! is_daemon_running ${RC_DAEMONS[i]} "${RC_PIDFILES[i]}" ; then
			if [[ -e "/etc/init.d/${service}" ]]; then
				( /etc/init.d/"${service}" stop &>/dev/null )
				break
			fi
		fi
	done
}

# int start-stop-daemon(...)
#
# Provide a wrapper to start-stop-daemon
# Return the result of start_daemon or stop_daemon depending on
# how we are called
start-stop-daemon() {
	local args="$( requote "$@" )" result i
	local cmd pidfile pid stopping signal nothing=false 
	local daemonfile="${svcdir}/daemons/${SVCNAME}"
	local -a RC_DAEMONS=() RC_PIDFILES=()

	[[ -e ${daemonfile} ]] && source "${daemonfile}"

	rc_setup_daemon_vars

	# We pass --oknodo and --test directly to start-stop-daemon and return
	if ${nothing}; then
		eval /sbin/start-stop-daemon "${args}"
		return "$?"
	fi

	if ${stopping}; then
		rc_stop_daemon
		result="$?"
		if [[ ${result} == "0" ]]; then
			# We stopped the daemon successfully
			# so we remove it from our state
			for (( i=0; i<${#RC_DAEMONS[@]}; i++ )); do
				# We should really check for valid cmd AND pidfile
				# But most called to --stop only set the pidfile
				if [[ ${RC_DAEMONS[i]} == "{cmd}" \
					|| ${RC_PIDFILES[i]}="${pidfile}" ]]; then
					unset RC_DAEMONS[i] RC_PIDFILES[i]
					RC_DAEMONS=( "${RC_DAEMONS[@]}" )
					RC_PIDFILES=( "${RC_PIDFILES[@]}" )
					break
				fi
			done
		fi
	else
		rc_start_daemon
		result="$?"
		if [[ ${result} == "0" ]]; then
			# We started the daemon sucessfully
			# so we add it to our state
			local max="${#RC_DAEMONS[@]}"
			for (( i=0; i<${max}; i++ )); do
				if [[ ${RC_DAEMONS[i]} == "{cmd}" \
					&& ${RC_PIDFILES[i]}="${pidfile}" ]]; then
					break
				fi
			done
			
			if [[ ${i} == "${max}" ]]; then
				RC_DAEMONS[max]="${cmd}"
				RC_PIDFILES[max]="${pidfile}"
			fi
		fi
	fi

	# Write the new list of daemon states for this service
	if [[ ${#RC_DAEMONS[@]} == "0" ]]; then
		[[ -f ${daemonfile} ]] && rm -f "${daemonfile}"
	else
		echo "RC_DAEMONS[0]=\"${RC_DAEMONS[0]}\"" > "${daemonfile}"
		echo "RC_PIDFILES[0]=\"${RC_PIDFILES[0]}\"" >> "${daemonfile}"

		for (( i=1; i<${#RC_DAEMONS[@]}; i++ )); do
			echo "RC_DAEMONS[${i}]=\"${RC_DAEMONS[i]}\"" >> "${daemonfile}"
			echo "RC_PIDFILES[${i}]=\"${RC_PIDFILES[i]}\"" >> "${daemonfile}"
		done
	fi

	return "${result}"
}

# vim:ts=4
