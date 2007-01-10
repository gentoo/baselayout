# Copyright 1999-2007 Gentoo Foundation 
# Distributed under the terms of the GNU General Public License v2

# RC functions to work with daemons
# Basically we're a fancy wrapper for start-stop-daemon
# and should be called as such. This means that our init scripts
# should work as is with zero modification :)

RC_GOT_DAEMON="yes"

[[ ${RC_GOT_FUNCTIONS} != "yes" ]] && . /sbin/functions.sh
[[ ${RC_GOT_SERVICES} != "yes" ]] && . "${svclib}/sh/rc-services.sh"

RC_WAIT_ON_START="0.2"
RC_WAIT_ON_STOP="5"

# void rc_shift_args(void)
#
# Proccess vars - makes things easier by using the shift command
# and indirect variables
rc_shift_args() {
	local addvar=
	
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

		# Try and seperate = out
		if [[ $1 == *"="* ]] ; then
			local x1=${1%%=*} x2=${1#*=}
			shift
			set -- "${x1}" "${x2}" "$@"
		fi

		# s-s-d uses getopt_long, so it could match against any
		# unqiue abbreviation ..... which sucks!
		case "$1" in
			-S|--start)
				stopping=false
				;;
			-K|--sto*)
				stopping=true
				;;
			-n|--na*)
				addvar="name"
				name=
				;;
			-x|--e*|-a|--starta*)
				addvar="cmd"
				cmd=
				;;
			-p|--p*)
				addvar="pidfile"
				pidfile=
				;;
			-b|--b*)
				background=true
				;;
			-m|--m*)
				makepidfile=true
				;;
			-R|--r*)
				addvar="retry"
				retry=
				;;
			-s|--si*)
				addvar="signal"
				signal=
				;;
			-t|--t*|-o|--o*)
				nothing=true
				;;
		esac
		shift
	done
}	

# void rc_setup_daemon_vars(void)
#
# Setup our vars based on the start-stop-daemon command
rc_setup_daemon_vars() {
	local -a sargs=( "${args%% \'--\' *}" ) eargs=()
	local x="${args// \'--\' /}" i=
	[[ ${x} != "${args}" ]] && eargs=( "${args##* \'--\' }" )

	eval rc_shift_args "${sargs[@]}"

	# We may want to launch the daemon with a custom command
	# This is mainly useful for debugging with apps like valgrind, strace
	local bash_service=$(bash_variable "${SVCNAME}")
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

# int rc_start_daemon(void)
#
# We don't do anyting fancy - just pass the given options
# to start-stop-daemon and return the value
rc_start_daemon() {
	local retval=
	
	eval /sbin/start-stop-daemon "${args}"
	retval=$?

	[[ ${retval} != 0 ]] && return ${retval}
	[[ ${RC_WAIT_ON_START} == "0" ]] && return ${retval}

	# We pause for RC_WAIT_ON_START seconds and then
	# check if the daemon is still running - this is mainly
	# to handle daemons who launch and then fail due to invalid
	# configuration files
	LC_ALL=C sleep "${RC_WAIT_ON_START}"

	local opts="--test --stop"
	[[ -n ${cmd} && -z ${name} ]] && opts="${opts} --exec \"${cmd}\""
	[[ -n ${pidfile} ]] && opts="${opts} --pidfile \"${pidfile}\""
	[[ -n ${name} ]] && opts="${opts} --name \"${name}\""
	eval /sbin/start-stop-daemon ${opts} >/dev/null && return 0

	[[ -f ${pidfile} ]] && rm -f "${pidfile}"
	return 1 
}

# bool rc_stop_daemon(void)
#
# We basically use a default schedule here if one is not supplied.
# If we are successful, then we clean up the pidfile if the daemon didn't.
rc_stop_daemon() {
	local retryargs=
	[[ -z ${retry} && ${RC_wAIT_ON_STOP:-5} -gt 0 ]] \
		&& retryargs="--retry ${signal:--TERM}/${RC_WAIT_ON_STOP:-5}"

	eval /sbin/start-stop-daemon ${retryargs} "${args}"
	local retval=$?
	[[ ${retval} != 0 ]] && return ${retval}

	# Remove the pidfile if the process didn't
	[[ -f ${pidfile} ]] && rm -f "${pidfile}"
	return 0
}

# void update_service_status(char *service)
#
# Loads the service state file and ensures that all listed daemons are still
# running - hopefully on their correct pids too
# If not, we stop the service
update_service_status() {
	local service="$1" daemonfile="${svcdir}/daemons/$1" i=
	local -a RC_DAEMONS=() RC_PIDFILES=() RC_NAMES=()

	# We only care about marking started services as stopped if the daemon(s)
	# for it are no longer running
	! service_started "${service}" && return
	[[ ! -f ${daemonfile} ]] && return

	# OK, now check that every daemon launched is active
	# If the --start command was any good a pidfile was specified too
	. "${daemonfile}"
	for (( i=0; i<${#RC_DAEMONS[@]}; i++ )); do
		local opts="--test --stop"
		[[ -n ${RC_DAEMONS[i]} && -z ${RC_NAMES[i]} ]] \
			&& opts="${opts} --exec \"${RC_DAEMONS[i]}"\"
		[[ -n ${RC_PIDFILES[i]} ]] \
			&& opts="${opts} --pidfile \"${RC_PIDFILES[i]}\""
		[[ -n ${RC_NAMES[i]} ]] \
			&& opts="${opts} --name \"${RC_NAMES[i]}\""
		if ! eval /sbin/start-stop-daemon ${opts} >/dev/null ; then
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
	local args=$(requote "$@") retval= i=
	local cmd= name= pidfile= pid= stopping= signal= nothing=false
	local background=false makepidfile=false retry=
	local daemonfile=
	local -a RC_DAEMONS=() RC_PIDFILES=() RC_NAMES=()

	if [[ -n ${SVCNAME} ]] ; then
		daemonfile="${svcdir}/daemons/${SVCNAME}"
		[[ -e ${daemonfile} ]] && . "${daemonfile}"
	fi

	rc_setup_daemon_vars

	# We pass --oknodo and --test directly to start-stop-daemon and return
	if ${nothing}; then
		eval /sbin/start-stop-daemon "${args}"
		return $?
	fi

	if ${stopping}; then
		rc_stop_daemon
		retval=$?
		if [[ ${retval} == 0 && -n ${daemonfile} ]]; then
			# We stopped the daemon successfully
			# so we remove it from our state
			for (( i=0; i<${#RC_DAEMONS[@]}; i++ )); do
				# We should really check for valid cmd AND pidfile
				# But most called to --stop only set the pidfile
				if [[ ${RC_DAEMONS[i]} == "${cmd}" \
					|| ${RC_PIDFILES[i]} == "${pidfile}" ]]; then
					unset RC_DAEMONS[i] RC_PIDFILES[i] RC_NAMES[i]
					RC_DAEMONS=( "${RC_DAEMONS[@]}" )
					RC_PIDFILES=( "${RC_PIDFILES[@]}" )
					RC_NAMES=( "${RC_NAMES[@]}" )
					break
				fi
			done
		fi
	else
		rc_start_daemon
		retval=$?
		if [[ ${retval} == 0 && -n ${daemonfile} ]]; then
			# We started the daemon sucessfully
			# so we add it to our state
			local max="${#RC_DAEMONS[@]}"
			for (( i=0; i<${max}; i++ )); do
				if [[ ${RC_DAEMONS[i]} == "${cmd}" \
					&& ${RC_PIDFILES[i]} == "${pidfile}" ]]; then
					break
				fi
			done
			
			if [[ ${i} == "${max}" ]]; then
				RC_DAEMONS[max]="${cmd}"
				RC_PIDFILES[max]="${pidfile}"
				RC_NAMES[max]="${name}"
			fi
		fi
	fi

	# Write the new list of daemon states for this service
	if [[ ${#RC_DAEMONS[@]} == "0" ]]; then
		[[ -f ${daemonfile} ]] && rm -f "${daemonfile}"
	elif [[ -n ${daemonfile} ]] ; then
		echo "RC_DAEMONS[0]='${RC_DAEMONS[0]}'" > "${daemonfile}"
		echo "RC_PIDFILES[0]='${RC_PIDFILES[0]}'" >> "${daemonfile}"
		echo "RC_NAMES[0]='${RC_NAMES[0]}'" >> "${daemonfile}"

		for (( i=1; i<${#RC_DAEMONS[@]}; i++ )); do
			echo "RC_DAEMONS[${i}]='${RC_DAEMONS[i]}'" >> "${daemonfile}"
			echo "RC_PIDFILES[${i}]='${RC_PIDFILES[i]}'" >> "${daemonfile}"
			echo "RC_NAMES[${i}]='${RC_NAMES[i]}'" >> "${daemonfile}"
		done
	fi

	return ${retval}
}

# vim: set ts=4 :
