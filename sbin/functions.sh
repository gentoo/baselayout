# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header$

RC_GOT_FUNCTIONS="yes"

# daemontools dir
SVCDIR="/var/lib/supervise"

# Check /etc/conf.d/rc for a description of these ...
svcdir="/var/lib/init.d"
svclib="/lib/rcscripts"
svcmount="no"
svcfstype="tmpfs"
svcsize=1024

# Different types of dependencies
deptypes="need use"
# Different types of order deps
ordtypes="before after"

#
# Internal variables
#

# Dont output to stdout?
RC_QUIET_STDOUT="no"

# Should we use color?
RC_NOCOLOR="no"
# Can the terminal handle endcols?
RC_ENDCOL="yes"

#
# Default values for rc system
#
RC_TTY_NUMBER=11
RC_NET_STRICT_CHECKING="no"
RC_PARALLEL_STARTUP="no"
RC_USE_CONFIG_PROFILE="yes"

# Override defaults with user settings ...
[ -f /etc/conf.d/rc ] && source /etc/conf.d/rc

# void splash(...)
#
#  Notify bootsplash/splashutils/gensplash/whatever about
#  important events.
#
splash() {
	return 0
}

# This will override the splash() function...
[ -f /sbin/splash-functions.sh ] && source /sbin/splash-functions.sh

# void get_bootconfig()
#
#    Get the BOOTLEVEL and SOFTLEVEL by setting
#    'bootlevel' and 'softlevel' via kernel
#    parameters.
#
get_bootconfig() {
	local copt=
	local newbootlevel=
	local newsoftlevel=

	for copt in $(< /proc/cmdline)
	do
		case "${copt%=*}" in
			"bootlevel")
				newbootlevel="${copt##*=}"
				;;
			"softlevel")
				newsoftlevel="${copt##*=}"
				;;
		esac
	done

	if [ -n "${newbootlevel}" ]
	then
		export BOOTLEVEL="${newbootlevel}"
	else
		export BOOTLEVEL="boot"
	fi

	if [ -n "${newsoftlevel}" ]
	then
		export DEFAULTLEVEL="${newsoftlevel}"
	else
		export DEFAULTLEVEL="default"
	fi

	return 0
}

setup_defaultlevels() {
	get_bootconfig
	
	if get_bootparam "noconfigprofile"
	then
		export RC_USE_CONFIG_PROFILE="no"
	
	elif get_bootparam "configprofile"
	then
		export RC_USE_CONFIG_PROFILE="yes"
	fi

	if [ "${RC_USE_CONFIG_PROFILE}" = "yes" -a -n "${DEFAULTLEVEL}" ] && \
	   [ -d "/etc/runlevels/${BOOTLEVEL}.${DEFAULTLEVEL}" -o \
	     -L "/etc/runlevels/${BOOTLEVEL}.${DEFAULTLEVEL}" ]
	then
		export BOOTLEVEL="${BOOTLEVEL}.${DEFAULTLEVEL}"
	fi
									
	if [ -z "${SOFTLEVEL}" ]
	then
		if [ -f "${svcdir}/softlevel" ]
		then
			export SOFTLEVEL="$(< ${svcdir}/softlevel)"
		else
			export SOFTLEVEL="${BOOTLEVEL}"
		fi
	fi

	return 0
}

# void get_libdir(void)
#
#    prints the current libdir {lib,lib32,lib64}
#
get_libdir()
{
	if [ -n "${CONF_LIBDIR_OVERRIDE}" ]; then
		CONF_LIBDIR="${CONF_LIBDIR_OVERRIDE}"
	elif [ -x "/usr/bin/portageq" ]; then
		CONF_LIBDIR="$(/usr/bin/portageq envvar CONF_LIBDIR)"
	fi
	echo ${CONF_LIBDIR:=lib}
}

# void esyslog(char* priority, char* tag, char* message)
#
#    use the system logger to log a message
#
esyslog() {
	local pri=
	local tag=
	
	if [ -x /usr/bin/logger ]
	then
		pri="$1"
		tag="$2"
		
		shift 2
		[ -z "$*" ] && return 0
		
		/usr/bin/logger -p "${pri}" -t "${tag}" -- "$*"
	fi

	return 0
}

# void einfo(char* message)
#
#    show an informative message (with a newline)
#
einfo() {
	if [ "${RC_QUIET_STDOUT}" != "yes" ]
	then
		echo -e " ${GOOD}*${NORMAL} ${*}"
	fi

	return 0
}

# void einfon(char* message)
#
#    show an informative message (without a newline)
#
einfon() {
	if [ "${RC_QUIET_STDOUT}" != "yes" ]
	then
		echo -ne " ${GOOD}*${NORMAL} ${*}"
	fi

	return 0
}

# void ewarn(char* message)
#
#    show a warning message + log it
#
ewarn() {
	if [ "${RC_QUIET_STDOUT}" = "yes" ]
	then
		echo " ${*}"
	else
		echo -e " ${WARN}*${NORMAL} ${*}"
	fi

	# Log warnings to system log
	esyslog "daemon.warning" "rc-scripts" "${*}"

	return 0
}

# void eerror(char* message)
#
#    show an error message + log it
#
eerror() {
	if [ "${RC_QUIET_STDOUT}" = "yes" ]
	then
		echo " ${*}" >/dev/stderr
	else
		echo -e " ${BAD}*${NORMAL} ${*}"
	fi

	# Log errors to system log
	esyslog "daemon.err" "rc-scripts" "${*}"

	return 0
}

# void ebegin(char* message)
#
#    show a message indicating the start of a process
#
ebegin() {
	if [ "${RC_QUIET_STDOUT}" != "yes" ]
	then
		if [ "${RC_ENDCOL}" = "yes" ]
		then
			echo -e " ${GOOD}*${NORMAL} ${*}..."
		else
			echo -ne " ${GOOD}*${NORMAL} ${*}..."
		fi
	fi

	return 0
}

# void eend(int error, char* errstr)
#
#    indicate the completion of process
#    if error, show errstr via eerror
#
eend() {
	local retval=
	
	if [ "$#" -eq 0 ] || ([ -n "$1" ] && [ "$1" -eq 0 ])
	then
		if [ "${RC_QUIET_STDOUT}" != "yes" ]
		then
			echo -e "${ENDCOL}  ${BRACKET}[ ${GOOD}ok${BRACKET} ]${NORMAL}"
		fi
	else
		retval="$1"
		
		if [ -c /dev/null ] ; then
			rc_splash "stop" &>/dev/null &
		else
			rc_splash "stop" &
		fi
		
		if [ "$#" -ge 2 ]
		then
			shift
			eerror "${*}"
		fi
		if [ "${RC_QUIET_STDOUT}" != "yes" ]
		then
			echo -e "${ENDCOL}  ${BRACKET}[ ${BAD}!!${BRACKET} ]${NORMAL}"
			# extra spacing makes it easier to read
			echo
		fi
		return ${retval}
	fi

	return 0
}

# void ewend(int error, char *warnstr)
#
#    indicate the completion of process
#    if error, show warnstr via ewarn
#
ewend() {
	local retval=
	
	if [ "$#" -eq 0 ] || ([ -n "$1" ] && [ "$1" -eq 0 ])
	then
		if [ "${RC_QUIET_STDOUT}" != "yes" ]
		then
			echo -e "${ENDCOL}  ${BRACKET}[ ${GOOD}ok${BRACKET} ]${NORMAL}"
		fi
	else
		retval="$1"
		if [ "$#" -ge 2 ]
		then
			shift
			ewarn "${*}"
		fi
		if [ "${RC_QUIET_STDOUT}" != "yes" ]
		then
			echo -e "${ENDCOL}  ${BRACKET}[ ${WARN}!!${BRACKET} ]${NORMAL}"
			# extra spacing makes it easier to read
			echo
		fi
		return "${retval}"
	fi

	return 0
}

# bool wrap_rcscript(full_path_and_name_of_rc-script)
#
#    check to see if a given rc-script has syntax errors
#    zero == no errors
#    nonzero == errors
#
wrap_rcscript() {
	local retval=1
	local myservice="${1##*/}"

	( echo "function test_script() {" ; cat "$1"; echo "}" ) \
		> "${svcdir}/${myservice}-$$"

	if source "${svcdir}/${myservice}-$$"
	then
		test_script
		retval=0
	fi
	rm -f "${svcdir}/${myservice}-$$"
	
	return "${retval}"
}

# char *KV_major(string)
#
#    Return the Major version part of given kernel version.
#
KV_major() {
	local KV=
	
	[ -z "$1" ] && return 1

	KV="$(echo "$1" | \
		awk '{ tmp = $0; gsub(/^[0-9\.]*/, "", tmp); sub(tmp, ""); print }')"
	echo "${KV}" | awk -- 'BEGIN { FS = "." } { print $1 }'

	return 0
}

# char *KV_minor(string)
#
#    Return the Minor version part of given kernel version.
#
KV_minor() {
	local KV=
	
	[ -z "$1" ] && return 1

	KV="$(echo "$1" | \
		awk '{ tmp = $0; gsub(/^[0-9\.]*/, "", tmp); sub(tmp, ""); print }')"
	echo "${KV}" | awk -- 'BEGIN { FS = "." } { print $2 }'

	return 0
}

# char *KV_micro(string)
#
#    Return the Micro version part of given kernel version.
#
KV_micro() {
	local KV=
	
	[ -z "$1" ] && return 1

	KV="$(echo "$1" | \
		awk '{ tmp = $0; gsub(/^[0-9\.]*/, "", tmp); sub(tmp, ""); print }')"
	echo "${KV}" | awk -- 'BEGIN { FS = "." } { print $3 }'

	return 0
}

# int KV_to_int(string)
#
#    Convert a string type kernel version (2.4.0) to an int (132096)
#    for easy compairing or versions ...
#
KV_to_int() {
	local KV_MAJOR=
	local KV_MINOR=
	local KV_MICRO=
	local KV_int=

	[ -z "$1" ] && return 1

	KV_MAJOR="$(KV_major "$1")"
	KV_MINOR="$(KV_minor "$1")"
	KV_MICRO="$(KV_micro "$1")"
	KV_int="$((KV_MAJOR * 65536 + KV_MINOR * 256 + KV_MICRO))"

	# We make version 2.2.0 the minimum version we will handle as
	# a sanity check ... if its less, we fail ...
	if [ "${KV_int}" -ge 131584 ]
	then
		echo "${KV_int}"

		return 0
	fi

	return 1
}

# int get_KV()
#
#    return the kernel version (major, minor and micro concated) as an integer
#
get_KV() {
	local KV="$(uname -r)"

	echo "$(KV_to_int "${KV}")"

	return $?
}

# bool get_bootparam(param)
#
#   return 0 if gentoo=param was passed to the kernel
#
#   EXAMPLE:  if get_bootparam "nodevfs" ; then ....
#
get_bootparam() {
	local x copt params retval=1

	[ ! -r "/proc/cmdline" ] && return 1
	
	for copt in $(< /proc/cmdline)
	do
		if [ "${copt%=*}" = "gentoo" ]
		then
			params="$(gawk -v PARAMS="${copt##*=}" '
				BEGIN {
					split(PARAMS, nodes, ",")
					for (x in nodes)
						print nodes[x]
				}')"
			
			# Parse gentoo option
			for x in ${params}
			do
				if [ "${x}" = "$1" ]
				then
#					echo "YES"
					retval=0
				fi
			done
		fi
	done
	
	return ${retval}
}

# Safer way to list the contents of a directory,
# as it do not have the "empty dir bug".
#
# char *dolisting(param)
#
#    print a list of the directory contents
#
#    NOTE: quote the params if they contain globs.
#          also, error checking is not that extensive ...
#
dolisting() {
	local x=
	local y=
	local tmpstr=
	local mylist=
	local mypath="${*}"

	if [ "${mypath%/\*}" != "${mypath}" ]
	then
		mypath="${mypath%/\*}"
	fi
	
	for x in ${mypath}
	do
		[ ! -e "${x}" ] && continue
		
		if [ ! -d "${x}" ] && ( [ -L "${x}" -o -f "${x}" ] )
		then
			mylist="${mylist} $(ls "${x}" 2> /dev/null)"
		else
			[ "${x%/}" != "${x}" ] && x="${x%/}"
			
			cd "${x}"; tmpstr="$(ls)"
			
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
#    save the settings ("optstring") for "option"
#
save_options() {
	local myopts="$1"
	
	shift
	if [ ! -d "${svcdir}/options/${myservice}" ]
	then
		mkdir -p -m 0755 "${svcdir}/options/${myservice}"
	fi
	
	echo "$*" > "${svcdir}/options/${myservice}/${myopts}"

	return 0
}

# char *get_options(char *option)
#
#    get the "optstring" for "option" that was saved
#    by calling the save_options function
#
get_options() {
	if [ -f "${svcdir}/options/${myservice}/$1" ]
	then
		echo "$(< ${svcdir}/options/${myservice}/$1)"
	fi

	return 0
}

# char *add_suffix(char * configfile)
#
#    Returns a config file name with the softlevel suffix
#    appended to it.  For use with multi-config services.
add_suffix() {
	if [ "${RC_USE_CONFIG_PROFILE}" = "yes" -a -e "$1.${DEFAULTLEVEL}" ]
	then
		echo "$1.${DEFAULTLEVEL}"
	else
		echo "$1"
	fi

	return 0
}

if [ -z "${EBUILD}" ]
then
	# Setup a basic $PATH.  Just add system default to existing.
	# This should solve both /sbin and /usr/sbin not present when
	# doing 'su -c foo', or for something like:  PATH= rcscript start
	PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/sbin:${PATH}"

	if [ "$(/sbin/consoletype 2> /dev/null)" = "serial" ]
	then
		# We do not want colors/endcols on serial terminals
		RC_NOCOLOR="yes"
		RC_ENDCOL="no"
	fi
	
	for arg in $*
	do
		case "${arg}" in
			# Lastly check if the user disabled it with --nocolor argument
			--nocolor)
				RC_NOCOLOR="yes"
				;;
		esac
	done

	if [ -r "/proc/cmdline" ]
	then
		setup_defaultlevels
	fi
else
	# Should we use colors ?
	if [[ $* != *depend* ]]; then
		# Check user pref in portage
		RC_NOCOLOR="$(portageq envvar NOCOLOR 2>/dev/null)"
		[ "${RC_NOCOLOR}" = "true" ] && RC_NOCOLOR="yes"
	else
		# We do not want colors or stty to run during emerge depend
		RC_NOCOLOR="yes"
		RC_ENDCOL="no"
	fi
fi

# Setup ENDCOL so that all our calls to eend line up the [ ok ]
if [ "${RC_ENDCOL}" == "yes" ] ; then
	COLS=${COLUMNS:-0}		# bash's internal COLUMNS variable
	(( COLS == 0 )) && COLS=$(stty size 2>/dev/null | cut -d' ' -f2)
	(( COLS -= 7 ))			# width of [ ok ]
	if (( COLS <= 0 )); then
		# Sanity check ... with serial consoles and such,
		# COLS may up being negative ...
		(( COLS = 80 ))
	fi
	ENDCOL=$'\e[A\e['${COLS}'G'
else
	ENDCOL=""
fi

# Setup the colors so our messages all look pretty
if [ "${RC_NOCOLOR}" = "yes" ]; then
	unset GOOD WARN BAD NORMAL HILITE BRACKET
else
	GOOD=$'\e[32;01m'
	WARN=$'\e[33;01m'
	BAD=$'\e[31;01m'
	NORMAL=$'\e[0m'
	HILITE=$'\e[36;01m'
	BRACKET=$'\e[34;01m'
fi

# vim:ts=4
