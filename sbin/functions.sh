# Copyright 1999-2004 Gentoo Technologies, Inc.
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


#
# Default values for rc system
#
RC_TTY_NUMBER=11
RC_NET_STRICT_CHECKING="no"
RC_PARALLEL_STARTUP="no"
RC_USE_CONFIG_PROFILE="yes"

# Override defaults with user settings ...
[ -f /etc/conf.d/rc ] && source /etc/conf.d/rc


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

#
# void splash_init (void)
#
splash_init() {
	pb_init=0
	pb_count=0
	pb_scripts=0
	pb_rate=0

	if [ ! -x /sbin/splash ] || \
	   [ -e /proc/version -a ! -e /proc/splash ]
	then
		return 0
	fi
	
	if [ -f /etc/conf.d/bootsplash.conf ]
	then
		. /etc/conf.d/bootsplash.conf
		if [ -n "${PROGRESS_SYSINIT_RATE}" ]
		then
			rate=$((65535*${PROGRESS_SYSINIT_RATE}/100))
		fi
	fi
	
	if [ "${RUNLEVEL}" = "S" ]
	then
		pb_scripts=5
		pb_rate=16383
		[ -n "${rate}" ] && pb_rate="${rate}"
	fi

	export pb_init pb_count pb_scripts pb_rate
}

#
# void splash_calc (void)
#
splash_calc() {
	pb_runs=($(dolisting "/etc/runlevels/${SOFTLEVEL}/"))
	pb_runb=($(dolisting "/etc/runlevels/${BOOTLEVEL}/"))
	pb_scripts=${#pb_runs[*]}
	pb_boot=${#pb_runb[*]}

	[ ! -e /proc/splash -o ! -x /sbin/splash ] && return 0

	if [ -f /etc/conf.d/bootsplash.conf ]
	then
		. /etc/conf.d/bootsplash.conf

		if [ -n "${PROGRESS_SYSINIT_RATE}" ]
		then
			init_rate=$((65535*${PROGRESS_SYSINIT_RATE}/100))
		fi
		
		if [ -n "${PROGRESS_BOOT_RATE}" ]
		then
			boot_rate=$((65535*${PROGRESS_BOOT_RATE}/100))
		fi
	fi

	# In runlevel boot we have 5 already started scripts
	#
	if [ "${RUNLEVEL}" = "S" -a "${SOFTLEVEL}" = "boot" ]
	then
		pb_started=($(dolisting "${svcdir}/started/"))
		pb_scripts=$((${pb_boot} - ${#pb_started[*]}))
		pb_init=16383
		pb_rate=26213
		pb_count=0
		if [ -n "${init_rate}" -a -n "${boot_rate}" ]
		then
			pb_init="${init_rate}"
			pb_rate=$((${init_rate} + ${boot_rate}))
		fi
	elif [ "${SOFTLEVEL}" = "reboot" -o "${SOFTLEVEL}" = "shutdown" ]
	then
		pb_started=($(dolisting "${svcdir}/started/"))
		pb_scripts=${#pb_started[*]}
		pb_rate=65534
	else
		pb_init=26213
		pb_rate=65534
		if [ -n "${init_rate}" -a -n "${boot_rate}" ]
		then
			pb_init=$((${init_rate} + ${boot_rate}))
		fi
	fi
	
	echo "pb_init=${pb_init}" > "${svcdir}/progress"
	echo "pb_rate=${pb_rate}" >> "${svcdir}/progress"
	echo "pb_count=${pb_count}" >> "${svcdir}/progress"
	echo "pb_scripts=${pb_scripts}" >> "${svcdir}/progress"
}

#
# void splash_update (char *fsstate, char *myscript, char *action)
#
splash_update() {
	local fsstate="$1"
	local myscript="$2"
	local action="$3"
	
	[ ! -e /proc/splash -o ! -x /sbin/splash ] && return 0
	
	if [ "${fsstate}" = "inline" ]
	then
		/sbin/splash "${myscript}" "${action}"
		pb_count=$((${pb_count} + 1))

		# Only needed for splash_debug() 
		pb_execed="${pb_execed} ${myscript:-inline}"
	else
		# Update only runlevel scripts, no dependancies (only true for startup)
		if [ ! -L "${svcdir}/softscripts/${myscript}" ]
		then
			[ "${SOFTLEVEL}" != "reboot" -a \
			  "${SOFTLEVEL}" != "shutdown" ] && return
		fi
		# Source the current progress bar state
		[ -f "${svcdir}/progress" ] && source "${svcdir}/progress"

		# Do not update an already executed script
		for x in ${pb_execed}
		do
			[ "${x}" = "${myscript}" ] && return
		done	
		
		/sbin/splash "${myscript}" "${action}"
		pb_count=$((${pb_count} + 1))
		
		echo "pb_init=${pb_init}" > "${svcdir}/progress"
		echo "pb_rate=${pb_rate}" >> "${svcdir}/progress"
		echo "pb_count=${pb_count}" >> "${svcdir}/progress"
		echo "pb_scripts=${pb_scripts}" >> "${svcdir}/progress"
		echo "pb_execed=\"${pb_execed} ${myscript}\"" >> "${svcdir}/progress"
	fi
}

#
# void splash_debug (char *softlevel)
#
splash_debug() {
	local softlevel="$1"

	[ ! -e /proc/splash -o ! -x /sbin/splash ] && return 0
	
	if [ -f /etc/conf.d/bootsplash.conf ]
	then
		source /etc/conf.d/bootsplash.conf

		[ "${BOOTSPLASH_DEBUG}" = "yes" -a -n "${softlevel}" ] || return
		
		if [ -f "${svcdir}/progress" ]
		then
			cat "${svcdir}/progress" > "/var/log/bootsplash.${softlevel}"
		else
			echo "pb_init=${pb_init}" > "/var/log/bootsplash.${softlevel}"
			echo "pb_rate=${pb_rate}" >> "/var/log/bootsplash.${softlevel}"
			echo "pb_count=${pb_count}" >> "/var/log/bootsplash.${softlevel}"
			echo "pb_scripts=${pb_scripts}" >> "/var/log/bootsplash.${softlevel}"
			echo "pb_execed=\"${pb_execed}\"" >> "/var/log/bootsplash.${softlevel}"
		fi	
	fi
}

update_splash_wrappers() {
	if [ -x /sbin/splash ] && \
	   ([ ! -e /proc/version ] || \
	    [ -e /proc/version -a -e /proc/splash ])
	then
		rc_splash() {
			/sbin/splash $*
		}
		rc_splash_init() {
			splash_init $*
		}
		rc_splash_calc() {
			splash_calc $*
		}
		rc_splash_update() {
			splash_update $*
		}
		rc_splash_debug() {
			splash_debug $*
		}
	else
		rc_splash() {
			return 0
		}
		rc_splash_init() {
			return 0
		}
		rc_splash_calc() {
			return 0
		}
		rc_splash_update() {
			return 0
		}
		rc_splash_debug() {
			return 0
		}
	fi

	export rc_splash rc_splash_init rc_splash_calc \
		rc_splash_update rc_splash_debug
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
		if [ "${RC_NOCOLOR}" = "yes" ]
		then
			echo -ne " ${GOOD}*${NORMAL} ${*}..."
		else
			echo -e " ${GOOD}*${NORMAL} ${*}..."
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

	if source "${svcdir}/${myservice}-$$" &> /dev/null
	then
		test_script &> /dev/null
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

	[ ! -e "/proc/cmdline" ] && return 1
	
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

getcols() {
	echo "$2"
}

if [ -z "${EBUILD}" ]
then
	# Setup a basic $PATH.  Just add system default to existing.
	# This should solve both /sbin and /usr/sbin not present when
	# doing 'su -c foo', or for something like:  PATH= rcscript start
	PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/sbin:${PATH}"

	if [ "$(/sbin/consoletype 2> /dev/null)" = "serial" ]
	then
		# We do not want colors on serial terminals
		RC_NOCOLOR="yes"
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

	if [ -e "/proc/cmdline" ]
	then
		setup_defaultlevels
	fi

	update_splash_wrappers
else
	# Should we use colors ?
	if [ "${*/depend}" = "$*" ]
	then
		# Check user pref in portage
		RC_NOCOLOR="$(portageq envvar NOCOLOR 2>/dev/null)"
		
		[ "${RC_NOCOLOR}" = "true" ] && RC_NOCOLOR="yes"
	else
		# We do not want colors or stty to run during emerge depend
		RC_NOCOLOR="yes"
	fi                                                                                                                       
fi

if [ "${RC_NOCOLOR}" = "yes" ]
then
	COLS="25 80"
	ENDCOL=
	
	GOOD=
	WARN=
	BAD=
	NORMAL=
	HILITE=
	BRACKET=
	
	if [ -n "${EBUILD}" ] && [ "${*/depend}" = "$*" ]
	then
		stty cols 80 &>/dev/null
		stty rows 25 &>/dev/null
	fi
else
	COLS="`stty size 2> /dev/null`"
	COLS="`getcols ${COLS}`"
	COLS=$((${COLS} - 7))
	ENDCOL=$'\e[A\e['${COLS}'G'    # Now, ${ENDCOL} will move us to the end of the
	                               # column;  irregardless of character width
	
	GOOD=$'\e[32;01m'
	WARN=$'\e[33;01m'
	BAD=$'\e[31;01m'
	NORMAL=$'\e[0m'
	HILITE=$'\e[36;01m'
	BRACKET=$'\e[34;01m'
fi


# vim:ts=4
