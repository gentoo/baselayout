#!/bin/bash
# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
# $Header$


source /sbin/rc-daemon.sh

#state variables
svcpause="no"
svcrestart="no"

myscript="$1"
if [ -L $1 ]
then
	myservice="$(readlink $1)"
else
	myservice="$1"
fi

myservice="${myservice##*/}"
mylevel="$(cat ${svcdir}/softlevel)"


#set $IFACE to the name of the network interface if it is a 'net.*' script
IFACE=""
NETSERVICE=""
if [ "${myservice%%.*}" = "net" -a "${myservice##*.}" != "${myservice}" ]
then
	IFACE="${myservice##*.}"
	NETSERVICE="yes"
fi
		
# Source configuration files.
# (1) Source /etc/conf.d/basic to get common configuration.
# (2) Source /etc/conf.d/${myservice} to get initscript-specific
#     configuration (if it exists).
# (3) Source /etc/conf.d/net if it is a net.* service
# (4) Source /etc/rc.conf to pick up potentially overriding
#     configuration, if the system administrator chose to put it
#     there (if it exists).

[ -e /etc/conf.d/basic ]                  && source /etc/conf.d/basic

[ -e /etc/conf.d/${myservice} ]           && source "/etc/conf.d/${myservice}"

[ -e /etc/conf.d/net ]                    && \
[ "${myservice%%.*}" = "net" ]            && \
[ "${myservice##*.}" != "${myservice}" ]  && source /etc/conf.d/net

[ -e /etc/rc.conf ]                       && source /etc/rc.conf

usage() {
	local IFS="|"
	myline="Usage: ${myservice} { $* "
	echo
	eerror "${myline}}"
	eerror "       ${myservice} without arguments for full help"
}

stop() {
	#return success so the symlink gets removed
	return 0
}

start() {
	eerror "ERROR:  \"${myservice}\" does not have a start function."
	#return failure so the symlink doesn't get created
	return 1
}

restart() {
	svc_restart || return $?
}

status() {
	#dummy function
	return 0
}
			
svc_stop() {
	local x=""
	local mydep=""
	local mydeps=""
	local retval=0
	local ordservice=""
	if [ ! -L ${svcdir}/started/${myservice} ]
	then
		eerror "ERROR:  \"${myservice}\" has not yet been started."
		return 1
	fi

	# do not try to stop if it had already failed to do so on runlevel change
	if [ -L ${svcdir}/failed/${myservice} -a -d ${svcdir}/softscripts.new ]
	then
		exit 1
	fi

	#remove symlink to prevent recursion
	rm -f ${svcdir}/started/${myservice}

	if [ -L /etc/init.d/boot/${myservice} ]
	then
		ewarn "WARNING:  you are stopping a boot service."
	fi
	if [ "${NETSERVICE}" = "yes" ]
	then
		#net.* service
		if [ -L /etc/runlevels/boot/${myservice} -o \
		     -L /etc/runlevels/${mylevel}/${myservice} ]
		then
			local netcount="$(ls -1 ${svcdir}/started/net.* \
				2> /dev/null | egrep -c "\/net\..*[[:digit:]]+$")"

			if [ "${netcount}" -lt 1 -o "${RC_NET_STRICT_CHECKING}" = "yes" ]
			then
				mydeps="net"
			fi
		fi
		
		mydeps="${mydeps} ${myservice}"
	else
		mydeps="${myservice}"
	fi
	if [ "${svcpause}" = "yes" ]
	then
		mydeps=""
	fi
	for mydep in ${mydeps}
	do
		#do not stop a service if it 'use' the current sevice
		if [ -d ${svcdir}/need/${mydep} ] || \
		   ([ -d ${svcdir}/softscripts.new -a -d ${svcdir}/after/${mydep} ])
		then
			#on rc change, stop all services "after $myservice" first
			if [ -d ${svcdir}/softscripts.new ]
			then
				local servicelist="$(dolisting ${svcdir}/need/${mydep}/) \
					$(dolisting ${svcdir}/after/${mydep}/)"
			else
				local servicelist="$(dolisting ${svcdir}/need/${mydep}/)"
			fi
			for x in ${servicelist}
			do
				if [ ! -L ${x} ]
				then
					continue
				fi
				if [ ! -L ${svcdir}/started/${x##*/} ]
				then
					#service not currently running, continue
					continue
				fi
				if [ -L ${svcdir}/before/${x}/${mydep} -a \
				     -L ${svcdir}/softscripts.new/${x} ]
				then
					continue
				fi
				${x} stop
				if [ "$?" -ne 0 ]
				then
					#if we are halting the system, try and get it down as
					#clean as possible, else do not stop our service if
					#a dependent service did not stop.
					if [ "${SOFTLEVEL}" != "reboot" -a \
					     "${SOFTLEVEL}" != "shutdown" -a \
						 -L ${svcdir}/need/${mydep}/${x} ]
					then
						retval=1
					fi
					break
				fi
			done
		fi
	done

	if [ "${retval}" -ne 0 ]
	then
		eerror "ERROR:  problems stopping dependent services."
		eerror "        \"${myservice}\" is still up."
	else
		#now that deps are stopped, stop our service
		stop
		retval=$?
	fi
	
	if [ "${retval}" -ne 0 ]
	then
		#did we fail to stop? create symlink to stop multible attempts at
		#runlevel change
		if [ -d ${svcdir}/failed ]
		then
			ln -sf /etc/init.d/${myservice} ${svcdir}/failed/${myservice}
		fi
		#if we are halting the system, do it as cleanly as possible
		if [ "${SOFTLEVEL}" != "reboot" -a "${SOFTLEVEL}" != "shutdown" ]
		then
			ln -sf /etc/init.d/${myservice} ${svcdir}/started/${myservice}
		fi
	fi

	return ${retval}
}

svc_start() {
	local retval=0
	local startfail="no"
	local x=""
	local y=""
	local myserv=""
	local ordservice=""
	if [ ! -L ${svcdir}/started/${myservice} ]
	then
		#do not try to start if i have done so already on runlevel change
		if [ -L ${svcdir}/failed/${myservice} -a -d ${svcdir}/softscripts.old ]
		then
			exit 1
		fi
	
		#link first to prevent possible recursion
		ln -sf /etc/init.d/${myservice} ${svcdir}/started/${myservice}

		#on rc change, start all services "before $myservice" first
		if [ -d ${svcdir}/softscripts.old ]
		then
			startupservices="$(ineed ${myservice}) \
				$(valid_iuse ${myservice}) \
				$(valid_iafter ${myservice})"
		else
			startupservices="$(ineed ${myservice}) \
				$(valid_iuse ${myservice})"
		fi

		#start dependencies, if any
		for x in ${startupservices}
		do
			if [ "${x}" = "net" ]
			then
				local netservlist="$(dolisting "/etc/runlevels/boot/net.*") \
					$(dolisting "/etc/runlevels/${mylevel}/net.*")"
					
				for y in ${netservlist}
				do
					myserv="${y##*/}"
					if [ ! -L ${svcdir}/started/${myserv} ]
					then
						/etc/init.d/${myserv} start

						#a 'need' dependancy is critical for startup
						if [ "$?" -ne 0 -a -L ${svcdir}/need/${x}/${myservice} ]
						then
							local netcount="$(ls -1 ${svcdir}/started/net.* \
								2> /dev/null | egrep -c "\/net\..*[[:digit:]]+$")"
							
							if [ "${netcount}" -lt 1 -o "${RC_NET_STRICT_CHECKING}" = "yes" ]
							then
								startfail="yes"
							fi
						fi
					fi
				done
			else
				if [ ! -L ${svcdir}/started/${x} ]
				then
					/etc/init.d/${x} start

					#a 'need' dependacy is critical for startup
					if [ "$?" -ne 0 -a -L ${svcdir}/need/${x}/${myservice} ]
					then
						startfail="yes"
					fi
				fi
			fi
		done
		
		if [ "${startfail}" = "yes" ]
		then
			eerror "ERROR:  Problem starting needed services."
			eerror "        \"${myservice}\" was not started."
			retval=1
		fi
		
		#start service
		if [ -d ${svcdir}/broken/${myservice} -a "${retval}" -eq 0 ]
		then
			eerror "ERROR:  Some services needed are missing.  Run"
			eerror "        './${myservice} broken' for a list of those"
			eerror "        services.  \"${myservice}\" was not started."
			retval=1
		elif [ ! -d ${svcdir}/broken/${myservice} -a "${retval}" -eq 0 ]
		then
			start
			retval=$?
		fi

		if [ "${retval}" -ne 0 -a -d ${svcdir}/failed ]
		then
			ln -sf /etc/init.d/${myservice} ${svcdir}/failed/${myservice}
		fi

		#remove link if service didn't start; but only if we're not booting
		#if we're booting, we need to continue and do our best to get the
		#system up.
		if [ "${retval}" -ne 0 -a "${SOFTLEVEL}" != "boot" ]
		then
			rm -f ${svcdir}/started/${myservice}
		fi
		return ${retval}
	else
		ewarn "WARNING:  \"${myservice}\" has already been started."
		return 0
	fi
}

svc_restart() {
	svc_stop || return $?
	sleep 1
	svc_start || return $?
}

svc_status() {
	# The basic idea here is to have some sort of consistant
	# output in the status() function which scripts can use
	# as an generic means to detect status.  Any other output
	# should thus be formatted in the custom status() function
	# to work with the printed " * status:  foo".

	if [ -L ${svcdir}/started/${myservice} ]
	then
		einfo "status:  started"
	else
		eerror "status:  stopped"
	fi

	status
}

wrap_rcscript ${myscript} || {
	eerror "ERROR:  \"${myscript}\" has syntax errors in it; not executing..."
	exit 1
}

# set *after* wrap_rcscript, else we get duplicates.
opts="start stop restart"

source ${myscript}

# make sure whe have valid $opts
if [ -z "${opts}" ]
then
	opts="start stop restart"
fi

# does $1 depend on $2 ?
dependon() {
	if [ -L ${svcdir}/need/$2/$1 -o -L ${svcdir}/use/$2/$1 ]
	then
		return 0
	else
		return 1
	fi
}

needsme() {
	local x=""
	if [ -d ${svcdir}/need/$1 ]
	then
		for x in $(dolisting ${svcdir}/need/$1/)
		do
			if [ ! -L ${x} ]
			then
				continue
			fi
			echo "${x##*/}"
		done
	fi
}

usesme() {
	local x=""
	if [ -d ${svcdir}/use/$1 ]
	then
		for x in $(dolisting ${svcdir}/use/$1/)
		do
			if [ ! -L ${x} ]
			then
				continue
			fi
			echo "${x##*/}"
		done
	fi
}

ineed() {
	local x=""
	local z=""
	for x in $(dolisting ${svcdir}/need/*/$1)
	do
		if [ ! -L ${x} ]
		then
			continue
		fi
		z="${x%/*}"
		echo "${z##*/}"
	done
}

#this will give all the use's of the service, even if not in current or boot
#runlevels
iuse() {
    local x=""
    local z=""
    for x in $(dolisting ${svcdir}/use/*/$1)
    do
		if [ ! -L ${x} ]
		then
		    continue
		fi
		z="${x%/*}"
		echo "${z##*/}"
    done
}

#this will only give the valid use's for the service (they must be in the boot
#or current runlevel)
valid_iuse() {
	local x=""
	local y=""
	for x in $(iuse $1)
	do
		if [ -e /etc/runlevels/boot/${x} -o -e /etc/runlevels/${mylevel}/${x} ]
		then
			z="${x%/*}"
			echo "${z##*/}"
		fi
	done
}

#list of services that should start before $1 on rc change
iafter() {
	local x=""
	local z=""
	for x in $(dolisting ${svcdir}/after/*/$1)
	do
		if [ ! -L ${x} ]
		then
			continue
		fi
		z="${x%/*}"
		echo "${z##*/}"
	done
}

#valid services for current or boot rc level that should start
#before $1
valid_iafter() {
	local x=""
	local y=""
	for x in $(iafter $1)
	do
		if [ -e /etc/runlevels/boot/${x} -o -e /etc/runlevels/${mylevel}/${x} ]
		then
			z="${x%/*}"
			echo "${z##*/}"
		fi
	done
}

#list broken dependancies of type 'need'
broken() {
	local x=""
	if [ -d ${svcdir}/broken/$1 ]
	then
		for x in $(dolisting ${svcdir}/broken/$1/)
		do
			if [ ! -f ${x} ]
			then
				continue
			fi
			echo "${x##*/}"
		done
	fi
}

#call this with "needsme", "ineed", "usesme", "iuse" or "broken" as first arg
query() {
	local deps=""
	local x=""
	install -d -m0755 ${svcdir}/depcheck/$$
	if [ "$1" = "ineed" -a ! -L ${svcdir}/started/${myservice} ]
	then
		ewarn "WARNING:  \"${myservice}\" not running."
		ewarn "          NEED info may not be accurate."
	fi
	if [ "$1" = "iuse" -a ! -L ${svcdir}/started/${myservice} ]
	then
		ewarn "WARNING:  \"${myservice}\" not running."
		ewarn "          USE info may not be accurate."
	fi

	deps="${myservice}"
	while [ -n "${deps}" ]
	do
		deps="$($1 ${deps})"
		for x in ${deps}
		do
			if [ ! -e ${svcdir}/depcheck/$$/${x} ]
			then
				touch ${svcdir}/depcheck/$$/${x}
			fi
		done
	done
	for x in $(dolisting ${svcdir}/depcheck/$$/)
	do
		if [ ! -e ${x} ]
		then
			continue
		fi
		echo "${x##*/}"
	done
	rm -rf ${svcdir}/depcheck
}

svc_homegrown() {
	local arg="$1"
	local x=""
	# Walk through the list of available options, looking for the
	# requested one.
	for x in ${opts}
	do
		if [ "${x}" = "${arg}" ]
		then
			if typeset -F ${x} &>/dev/null
			then
				# Run the homegrown function
				${x}
				return $?
			else
				# This is a weak error message
				ewarn "WARNING:  function \"${x}\" doesn't exist."
				usage ${opts}
				exit 1
			fi
		fi
	done
	# If we're here, then the function wasn't in $opts.  This is
	# the same error message that used to be in the case statement
	# before homegrown functions were supported.
	eerror "ERROR:  wrong args. (  ${arg} / $* )"
	usage ${opts}
	exit 1
}

shift
if [ "$#" -lt 1 ]
then
	eerror "ERROR:  not enough args."
	usage ${opts}
	exit 1
fi
for arg in $*
do
	case ${arg} in
	--quiet)
		QUIET_STDOUT="yes"
		;;
	esac
done
for arg in $*
do
	case ${arg} in
	stop)
		svc_stop
		;;
	start)
		svc_start
		;;
	needsme|ineed|usesme|iuse|broken)
		query ${arg}
		;;
	status)
		svc_status
		;;
	zap)
		if [ -e ${svcdir}/started/${myservice} ]
		then
			einfo "Manually resetting ${myservice} to stopped state."
			rm -f ${svcdir}/started/${myservice}
		fi
		;;
	restart)
		svcrestart="yes"
		
		#create a snapshot of started services
		rm -rf ${svcdir}/snapshot/*
		cp ${svcdir}/started/* ${svcdir}/snapshot/
		
		#simple way to try and detect if the service use svc_{start,stop}
		#to restart if it have a custom restart() funtion.
		if [ -n "$(egrep 'restart()' /etc/init.d/${myservice})" ]
		then
			if [ -z "$(egrep 'svc_stop' /etc/init.d/${myservice})" -o \
			     -z "$(egrep 'svc_start' /etc/init.d/${myservice})" ]
			then
				echo
				ewarn "Please use 'svc_stop; svc_start' and not 'start; stop' to"
				ewarn "restart the service in its custom 'restart()' function."
				ewarn "Run ${myservice} without arguments for more info."
				echo
				svc_restart
			else
				restart
			fi
		else
			restart
		fi

		#restart dependancies as well
		if [ -L ${svcdir}/started/${myservice} ]
		then
			for x in $(dolisting ${svcdir}/snapshot/)
			do
				if [ ! -L ${svcdir}/started/${x##*/} ]
				then
					${x} start
				fi
			done
		fi
		svcrestart="no"
		;;
	pause)
		svcpause="yes"
		svc_stop
		svcpause="no"
		;;
	--quiet)
		;;
	*)
		# Allow for homegrown functions
		svc_homegrown ${arg}
		;;
	esac
done


# vim:ts=4
