#!/bin/bash
# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License, v2 or later
# $Header$


source /etc/init.d/functions.sh

#state variables
svcpause="no"
svcrestart="no"

myscript=${1}
if [ -L $1 ]
then
	myservice=`readlink ${1}`
else
	myservice=${1}
fi

myservice=${myservice##*/}
mylevel=`cat ${svcdir}/softlevel`


#set $IFACE to the name of the network interface if it is a 'net.*' script
IFACE=[]
NETSERVICE=[]
if [ "${myservice%%.*}" = "net" ] && [ "${myservice##*.}" != "$myservice" ]
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
[ -e /etc/conf.d/basic ]	&& source /etc/conf.d/basic
[ -e /etc/conf.d/${myservice} ] && source /etc/conf.d/${myservice}
[ -e /etc/conf.d/net ] && [ "${myservice%%.*}" = "net" ] && \
	[ "${myservice##*.}" != "$myservice" ] && source /etc/conf.d/net
[ -e /etc/rc.conf ]		&& source /etc/rc.conf

usage() {
	local IFS="|"
	myline="Usage: ${myservice} {$*"
	echo
	eerror "${myline}}"
	eerror "       ${myservice} without arguments for full help"
}

stop() {
	#return success so the symlink gets removed
	return 0
}

start() {
	einfo "${myservice} does not have a start function."
	#return failure so the symlink doesn't get created
	return 1
}

restart() {
	svc_restart || return $?
}
			
svc_stop() {
	local x=[]
	local stopfail="no"
	local mydep=[]
	local mydeps=[]
	local retval=0
	local depservice=[]
	if [ ! -L ${svcdir}/started/${myservice} ]
	then
		einfo "${myservice} has not yet been started."
		return 1
	fi

	# do not try to stop if it had already failed to do so on runlevel change
	if [ -L ${svcdir}/fails/${myservice} ] && [ -d ${svcdir}/softscripts.new ]
	then
		exit 1
	fi

	#remove symlink to prevent recursion
	rm -f ${svcdir}/started/${myservice}

	#stop all services that should be before on runlevel change
	for x in ${svcdir}/before/*/${myservice}
	do
		if [ ! -L ${x} ]
		then
			continue
		fi
		depservice=${x%/*}
		if [ -d ${svcdir}/softscripts.new ]
		then
			if [ ! -L ${svcdir}/softscripts.new/${depservice##*/} ] && \
			   [ -L ${svcdir}/started/${depservice##*/} ] && \
			   [ ! -L ${svcdir}/need/${depservice##*/}/${myservice} ] && \
			   [ ! -L ${svcdir}/use/${depservice##*/}/${myservice} ] && \
			   [ ! -L ${svcdir}/before/${myservice}/${depservice##*/} ]
			then
				/etc/init.d/${depservice##*/} stop
			fi
		fi
	done
	
	if [ -L /etc/init.d/boot/${myservice} ]
	then
		einfo "Warning: you are stopping a boot service."
	fi
	if [ "$NETSERVICE" = "yes" ]
	then
		#net.* service
		if [ -L /etc/runlevels/boot/${myservice} ] || [ -L /etc/runlevels/${mylevel}/${myservice} ]
		then
			mydeps="net $myservice"
		else
			mydeps=$myservice
		fi
	else
		mydeps=$myservice
	fi
	if [ "$svcpause" = "yes" ]
	then
		mydeps=""
	fi
	for mydep in $mydeps
	do
		#do not stop a service if it 'use' the current sevice
		for mytype in ${deptypes/use/}
		do
			if [ -d ${svcdir}/${mytype}/${mydep} ]
			then
				for x in ${svcdir}/${mytype}/${mydep}/*
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
					${x} stop
					if [ $? -ne 0 ]
					then
						#if we are halting the system, try and get it down as
						#clean as possible
						if [ "$SOFTLEVEL" != "reboot" ] && [ "$SOFTLEVEL" != "shutdown" ]
						then
							stopfail="yes"
						fi
						break
					fi
				done
				if [ "$stopfail" = "yes" ] && [ -L ${svcdir}/need/${mydep}/${x} ]
				then
					retval=1
				fi
			fi
		done
	done

	if [ $retval -ne 0 ]
	then
		eerror "Problems stopping dependent services.  \"${myservice}\" still up."
	else
		#now that deps are stopped, stop our service
		stop
		retval=$?
	fi
	
#stopping services that should be stopped after this service on runlevel change,
#cause first script to be run, to actually be run last, so a big no no.

	if [ $retval -ne 0 ]
	then
		#did we fail to stop? create symlink to stop multible attempts at
		#runlevel change
		if [ -d ${svcdir}/fails ]
		then
			ln -sf /etc/init.d/${myservice} ${svcdir}/fails/${myservice}
		fi
		#if we are halting the system, do it as cleanly as possible
		if [ "$SOFTLEVEL" != "reboot" ] && [ "$SOFTLEVEL" != "shutdown" ]
		then
			ln -sf /etc/init.d/${myservice} ${svcdir}/started/${myservice}
		fi
	fi
	return $retval
}

svc_start() {
	local retval=0
	local startfail="no"
	local x=[]
	local y=[]
	local myserv=[]
	local depservice=[]
	if [ ! -L ${svcdir}/started/${myservice} ]
	then
		#do not try to start if i have done so already on runlevel change
		if [ -L ${svcdir}/fails/${myservice} ] && [ -d ${svcdir}/softscripts.old ]
		then
			exit 1
		fi
	
		#link first to prevent possible recursion
		ln -sf /etc/init.d/${myservice} ${svcdir}/started/${myservice}
	
		#start anything that should be started before on runlevel change
		for x in ${svcdir}/after/*/${myservice}
		do
			if [ ! -L ${x} ]
			then
				continue
			fi
			depservice=${x%/*}
			if [ -d ${svcdir}/softscripts.old ]
			then
				if [ ! -L ${svcdir}/softscripts.old/${depservice##*/} ] && \
				   [ ! -L ${svcdir}/started/${depservice##*/} ] && \
				   [ -L ${svcdir}/softscripts/${depservice##*/} ] && \
				   [ ! -L ${svcdir}/need/${myservice}/${depservice##*/} ] && \
				   [ ! -L ${svcdir}/use/${myservice}/${depservice##*/} ] && \
				   [ ! -L ${svcdir}/after/${myservice}/${depservice##*/} ]
				then
					/etc/init.d/${depservice##*/} start
				fi
			fi
		done

		#start dependencies, if any
		for x in `ineed ${myservice}` `valid_iuse ${myservice}`
		do
			if [ "$x" = "net" ]
			then
				for y in /etc/runlevels/boot/net.* /etc/runlevels/${mylevel}/net.*
				do
					myserv=${y##*/}
					if [ ! -L ${svcdir}/started/${myserv} ]
					then
						/etc/init.d/${myserv} start

						#a 'need' dependacy is critical for the service to start
						if [ $? -ne 0 ] && [ -L ${svcdir}/need/${x}/${myservice} ]
						then
							startfail="yes"
						fi
					fi
				done
			else
				if [ ! -L ${svcdir}/started/${x} ]
				then
					/etc/init.d/${x} start

					#a 'need' dependacy is critical for the service to start
					if [ $? -ne 0 ] && [ -L ${svcdir}/need/${x}/${myservice} ]
					then
						startfail="yes"
					fi
				fi
			fi
		done
		
		if [ "$startfail" = "yes" ]
		then
			eerror "Problem starting needed services.  \"${myservice}\" was not started."
			retval=1
		fi
		
		#start service
		if [ -d ${svcdir}/broken/${myservice} ] && [ $retval -eq 0 ]
		then
			eerror "Some services needed are missing.  Run './${myservice} broken'"
			eerror "for a list of those services.  \"${myservice}\" was not started."
			retval=1
		elif [ ! -d ${svcdir}/broken/${myservice} ] && [ $retval -eq 0 ]
		then
			start
			retval=$?
		fi

		if [ $retval -ne 0 ]
		then
			if [ -d ${svcdir}/fails ]
			then
				ln -sf /etc/init.d/${myservice} ${svcdir}/fails/${myservice}
			fi
		fi

		#start anything that should be started after on runlevel change
		for x in ${svcdir}/before/*/${myservice}
		do
			if [ ! -L ${x} ]
			then
				continue
			fi
			depservice=${x%/*}
			if [ -d ${svcdir}/softscripts.old ]
			then
				if [ ! -L ${svcdir}/softscripts.old/${depservice##*/} ] && \
				   [ ! -L ${svcdir}/started/${depservice##*/} ] && \
				   [ -L ${svcdir}/softscripts/${depservice##*/} ] && \
				   [ ! -L ${svcdir}/need/${depservice##*/}/${myservice} ] && \
				   [ ! -L ${svcdir}/use/${depservice##*/}/${myservice} ] && \
				   [ ! -L ${svcdir}/before/${myservice}/${depservice##*/} ]
				then
					/etc/init.d/${depservice##*/} start
				fi
			fi
		done

		#remove link if service didn't start; but only if we're not booting
		#if we're booting, we need to continue and do our best to get the
		#system up.
		if [ $retval -ne 0 ] && [ "$SOFTLEVEL" != "boot" ]
		then
			rm ${svcdir}/started/${myservice}
		fi
		return $retval
	else
		einfo "${myservice} has already been started."
		return 1
	fi
}

svc_restart() {
	svc_stop || return $?
	sleep 1
	svc_start || return $?
}

wrap_rcscript ${myscript} || {
	einfo "${myscript} has syntax errors in it, not executing..."
	exit 1
}

if [ "$opts" = "" ]
then
	opts="start stop restart"
fi

needsme() {
	local x=[]
	if [ -d ${svcdir}/need/${1} ]
	then
		for x in ${svcdir}/need/${1}/*
		do
			if [ ! -L $x ]
			then
				continue
			fi
			echo ${x##*/}
		done
	fi
}

usesme() {
	local x=[]
	if [ -d ${svcdir}/use/${1} ]
	then
		for x in ${svcdir}/use/${1}/*
		do
			if [ ! -L $x ]
			then
				continue
			fi
			echo ${x##*/}
		done
	fi
}

ineed() {
	local x=[]
	local z=[]
	for x in ${svcdir}/need/*/${1}
	do
		if [ ! -L ${x} ]
		then
			continue
		fi
		z=${x%/*}
		echo ${z##*/}
	done
}

#this will give all the use's of the service, even if not in current or boot
#runlevels
iuse() {
    local x=[]
    local z=[]
    for x in ${svcdir}/use/*/${1}
    do
		if [ ! -L ${x} ]
		then
		    continue
		fi
		z=${x%/*}
		echo ${z##*/}
    done
}

#this will only give the valid use's for the service (they must be in the boot
#or current runlevel)
valid_iuse() {
	local x=[]
	local y=[]
	for x in `iuse ${1}`
	do
		if [ -e /etc/runlevels/boot/${x} ] || [ -e /etc/runlevels/${mylevel}/${x} ]
		then
			z=${x%/*}
			echo ${z##*/}
		fi
	done
}

#list broken dependancies of type 'need'
broken() {
	local x=[]
	if [ -d ${svcdir}/broken/${1} ]
	then
		for x in ${svcdir}/broken/${1}/*
		do
			if [ ! -f $x ]
			then
				continue
			fi
			echo ${x##*/}
		done
	fi
}

#call this with "needsme", "ineed", "usesme", "iuse" or "broken" as first arg
query() {
	local deps=[]
	local x=[]
	install -d -m0755 ${svcdir}/depcheck/$$
	if [ "$1" = "ineed" ] && [ ! -L ${svcdir}/started/${myservice} ]
	then
		einfo "Warning: ${myservice} not running. need info may not be accurate."
	fi
	if [ "$1" = "iuse" ] && [ ! -L ${svcdir}/started/${myservice} ]
	then
		einfo "Warning: ${myservice} not running. use info may not be accurate."
	fi

	deps="${myservice}"
	while [ "$deps" != "" ]
	do
		deps=`${1} ${deps}`
		for x in $deps
		do
			if [ ! -e ${svcdir}/depcheck/$$/${x} ]
			then
				touch ${svcdir}/depcheck/$$/${x}
			fi
		done
	done
	for x in ${svcdir}/depcheck/$$/*
	do
		if [ ! -e $x ]
		then
			continue
		fi
		echo ${x##*/}
	done
	rm -rf ${svcdir}/depcheck/
}

svc_homegrown() {
	local arg="$1"
	local x=[]
	# Walk through the list of available options, looking for the
	# requested one.
	for x in $opts; do
		if [ $x = "$arg" ]; then
			if typeset -F $x &>/dev/null; then
				# Run the homegrown function
				$x
				return $?
			else
				# This is a weak error message
				echo "Function $x doesn't exist."
				usage $opts
				exit 1
			fi
		fi
	done
	# If we're here, then the function wasn't in $opts.  This is
	# the same error message that used to be in the case statement
	# before homegrown functions were supported.
	echo "wrong args. (  $arg / $* )"
	usage $opts
	exit 1
}

shift
if [ $# -lt 1 ]
then
	echo "not enough args."
	usage $opts
	exit 1
fi
for arg in ${*}
do
	case $arg in
	stop)
		svc_stop
		;;
	start)
		svc_start
		;;
	needsme|ineed|usesme|iuse|broken)
		query $arg
		;;
	zap)
		if [ -e ${svcdir}/started/${myservice} ]
		then
			einfo "Manually resetting ${myservice} to stopped state."
			rm ${svcdir}/started/${myservice}
		fi
		;;
	restart)
		svcrestart="yes"
		#create a snapshot of started services
		rm -rf ${svcdir}/snapshot/*
		cp ${svcdir}/started/* ${svcdir}/snapshot/
		#simple way to try and detect if the service use svc_{start,stop} to restart
		#if it have a custom restart() funtion.
		if [ "`grep 'restart()' /etc/init.d/${myservice}`" ]
		then
			if [ -z "`grep svc_stop /etc/init.d/${myservice}`" ] || [ -z "`grep svc_start /etc/init.d/${myservice}`" ]
			then
				echo
				einfo "Please use 'svc_stop; svc_start' and not 'start; stop' to restart the service"
				einfo "in the custom 'restart()' function.  Run ${myservice} without arguments for"
				einfo "more info."
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
			for x in ${svcdir}/snapshot/*
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
	*)
		# Allow for homegrown functions
		svc_homegrown $arg
		;;
	esac
done


# vim:ts=4
