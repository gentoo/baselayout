# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# $Header$

# Setup a basic $PATH
[ -z "${PATH}" ] && \
	PATH="/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/sbin"

# Make sure that /sbin and /usr/sbin are in $PATH
[ "${PATH/^\/sbin:}" = "${PATH}" -a "${PATH/:\/sbin:}" = "${PATH}" ] && \
	PATH="/sbin:${PATH}"
[ "${PATH/^\/usr\/sbin:}" = "${PATH}" -a "${PATH/:\/usr\/sbin:}" = "${PATH}" ] && \
	PATH="/usr/sbin:${PATH}"

# daemontools dir
SVCDIR="/var/lib/supervise"

# rc-scripts dir
svcdir="/mnt/.init.d"

svcfstype="tmpfs"

# Size of $svcdir in KB
svcsize="1024"

# tmpfs mount point for diskless nodes
shmdir="/mnt/.shm"

# Different types of dependancies
deptypes="need use"

# Different types of order deps
ordtypes="before after"

#
# Internal variables
#

# Dont output to stdout?
QUIET_STDOUT="no"

#
# Default values for rc system
#
RC_NET_STRICT_CHECKING="no"

# Override defaults with user settings ...
[ -f /etc/conf.d/rc ] && source /etc/conf.d/rc


getcols() {
	echo "$2"
}

COLS="$(stty size 2>/dev/null)"
if [ "$COLS" = "0 0" ]
then
	# Fix for serial tty (bug #11557)
    COLS=80
    stty cols 80 &>/dev/null
    stty rows 24 &>/dev/null
else
    COLS="$(getcols ${COLS})"
fi
COLS=$((${COLS} -7))
ENDCOL=$'\e[A\e['${COLS}'G'
# Now, ${ENDCOL} will move us to the end of the column;
# irregardless of character width

NORMAL="\033[0m"
GOOD=$'\e[32;01m'
WARN=$'\e[33;01m'
BAD=$'\e[31;01m'
NORMAL=$'\e[0m'

HILITE=$'\e[36;01m'

esyslog() {
	if [ -x /usr/bin/logger ]
	then
		pri="$1"
		tag="$2"
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
	if [ "$#" -eq 0 ] || ([ -n "$1" ] && [ "$1" -eq 0 ])
	then
		if [ "${QUIET_STDOUT}" != "yes" ]
		then
			echo -e "${ENDCOL}  \e[34;01m[ ${GOOD}ok \e[34;01m]${NORMAL}"
		fi
	else
		local returnme="$1"
		if [ "$#" -ge 2 ]
		then
			shift
			eerror "${*}"
		fi
		if [ "${QUIET_STDOUT}" != "yes" ]
		then
			echo -e "${ENDCOL}  \e[34;01m[ ${BAD}!! \e[34;01m]${NORMAL}"
			#extra spacing makes it easier to read
			echo
		fi
		return ${returnme}
	fi
}

# void ewend(int error, char *errstr)
#
ewend() {
	if [ "$#" -eq 0 ] || ([ -n "$1" ] && [ "$1" -eq 0 ])
	then
		if [ "${QUIET_STDOUT}" != "yes" ]
		then
			echo -e "${ENDCOL}  \e[34;01m[ ${GOOD}ok \e[34;01m]${NORMAL}"
		fi
	else
		local returnme="$1"
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

	( echo "function test_script() {" ; cat $1; echo "}" ) > ${svcdir}/foo.sh

	if source ${svcdir}/foo.sh &>/dev/null
	then
		test_script &>/dev/null
		retval=0
	fi
	rm -f ${svcdir}/foo.sh
	return ${retval}
}

# int checkserver(void)
#
#    Return 0 (no error) if this script is executed 
#    onto the server, one otherwise.
#    See the boot section of /sbin/rc for more details.
# 
checkserver() {
	# Only do check if 'gentoo=adelie' is given as kernel param
	if get_bootparam "adelie"
	then
		[ "`cat ${svcdir}/hostname`" = "(none)" ] || return 1
	fi
	
	return 0
}

# int get_KV()
#
#   return the kernel version (major and minor concated) as a integer
#
get_KV() {
	local KV_MAJOR="`uname -r | cut -d. -f1`"
	local KV_MINOR="`uname -r | cut -d. -f2`"

	echo "${KV_MAJOR}${KV_MINOR}"
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
		if [ ! -d ${x} ] && ( [ -L ${x} -o -f ${x} ] )
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
	local myopts="$1"
	shift
	if [ ! -d ${svcdir}/options/${myservice} ]
	then
		install -d -m0755 ${svcdir}/options/${myservice}
	fi
	echo "$*" > ${svcdir}/options/${myservice}/${myopts}
}

# char *get_options(char *option)
#
#   get the "optstring" for "option" that was saved
#   by calling the save_options function
#
get_options() {
	if [ -f ${svcdir}/options/${myservice}/$1 ]
	then
		cat ${svcdir}/options/${myservice}/$1
	fi
}


# vim:ts=4
