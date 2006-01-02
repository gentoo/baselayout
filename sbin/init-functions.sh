# Copyright 1999-2006 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

# void try(command)
#
#   Try to execute 'command', if it fails, drop to a shell.
#
try() {
	local errstr
	local retval=0
	
	if [[ -c /dev/null ]] ; then
		errstr="$((eval $*) 2>&1 >/dev/null)"
	else
		errstr="$((eval $*) 2>&1)"
	fi
	retval=$?
	if [[ ${retval} -ne 0 ]] ; then
		splash "critical" &

		echo -e "${ENDCOL}${NORMAL}[${BAD} oops ${NORMAL}]"
		echo
		eerror "The \"${1}\" command failed with error:"
		echo
		echo "${errstr#*: }"
		echo
		eerror "Since this is a critical task, startup cannot continue."
		echo
		single_user
	fi
	
	return ${retval}
}

# bool check_statedir(dir)
#
#   Check that 'dir' exists, if not, drop to a shell.
#
check_statedir() {
	[[ -z $1 ]] && return 0

	if [[ ! -d $1 ]] && ! mkdir -p "$1" &>/dev/null ; then
		splash "critical" &
		echo
		eerror "For Gentoo to function properly, \"$1\" needs to exist."
		if [[ ${RC_FORCE_AUTO} == "yes" ]] ; then
			eerror "Attempting to create \"$1\" for you ..."
			mount -o remount,rw /
			mkdir -p "$1"
		fi
		if [[ ! -d $1 ]] ; then
			eerror "Please mount your root partition read/write, and execute:"
			echo
			eerror "  # mkdir -p $1"
			echo; echo
			single_user
		fi
	fi

	return 0
}

# void start_critical_service()
#
#   Start critical services needed for bootup
#
start_critical_service() {
	(
	local retval=
	local service=$1
	# Needed for some addons like dm-crypt that starts in critical services
	local myservice=$1

	source "/etc/init.d/${service}" || eerror "Failed to source /etc/init.d/${service}"
	retval=$?
	[[ ${retval} -ne 0 ]] && return "${retval}"
	[[ -e /etc/conf.d/${service} ]] && source "/etc/conf.d/${service}"
	source /etc/rc.conf

	start || eerror "Failed to start /etc/init.d/${service}"
	retval=$?

	return "${retval}"
	)
}


# vim:ts=4
