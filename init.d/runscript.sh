#!/bin/bash

source /etc/init.d/functions.sh
source /etc/rc.conf
svcdir=/dev/shm/.init.d

myscript=${1}
if [ -L $1 ]
then
	myservice=`readlink ${1}`
else
	myservice=${1}
fi

myservice=${myservice##*/}
mylevel=`cat ${svcdir}/softlevel`

[ -e /etc/conf.d/${myservice} ] && . /etc/conf.d/${myservice}

usage() {
	export IFS="|"
	myline="Usage: ${myservice} {$*"
	eerror "${myline}}"
}

stop() {
	#return success so the symlink gets removed
	return
}

start() {
	einfo "${myservice} does not have a start function."
	#return failure so the symlink doesn't get created
	return 1
}

svc_stop() {
	local x
	local stopfail
	local mydeps
	local mydep
	stopfail="no"
	if [ ! -L ${svcdir}/started/${myservice} ]
	then
		einfo "${myservice} has not yet been started."
		return 1
	fi		
	if [ -L /etc/init.d/boot/${myservice} ]
	then
		einfo "Warning: you are stopping a boot service."
	fi
	if [ "${myservice##*.}" != "$myservice" ]
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
	for mydep in $mydeps
	do
		if [ -d ${svcdir}/need/${mydep} ]
		then
			for x in ${svcdir}/need/${mydep}/*
			do
				if [ ! -L ${x} ]
					then
					continue	
				fi
				if [ ! -L ${svcdir}/started/${x##*/} ]
				then
					#service not currently running, continue
					rm ${x}
					continue
				fi
				${x} stop
				if [ $? -ne 0 ]
				then
					stopfail="yes"
					break
				else
					rm ${x}
				fi
			done
			if [ "$stopfail" = "yes" ]
			then
				einfo "Problems stopping dependent services.  ${myservice} still up."
				exit 1
			fi	
		fi
	done
	#now that deps are stopped, stop our service
	stop
	if [ $? -eq 0 ]
	then
		rm ${svcdir}/started/${myservice}
	else
		return $?
	fi
}

svc_start() {
	local retval
	local x
	local y
	local myserv
	if [ ! -L ${svcdir}/started/${myservice} ]
	then
		#link first to prevent possible recursion
		ln -s /etc/init.d/${myservice} ${svcdir}/started/${myservice}
		
		#start dependencies, if any
		for x in `ineed ${myservice}`
		do
			if [ "$x" = "net" ]
			then
				for y in /etc/runlevels/boot/net.* /etc/runlevels/${mylevel}/net.*
				do
					myserv=${y##*/}
					if [ ! -L ${svcdir}/started/${myserv} ]
					then
						/etc/init.d/${myserv} start
					fi
				done
			else	
				if [ ! -L ${svcdir}/started/${x} ]
				then
					/etc/init.d/${x} start
				fi
			fi
		done
		#start service
		start
		retval=$?
		
		#remove link if service didn't start; but only if we're not booting
		#if we're booting, we need to continue and do our best to get the
		#system up.  
		if [ "$SOFTLEVEL" = "boot" ]
		then
			return $retval
		elif [ $retval -ne 0 ]
		then
			rm ${svcdir}/started/${myservice}
			return $retval
		fi
	else
		einfo "${myservice} has already been started."
		return 1
	fi
}

source ${myscript}
if [ "$opts" = "" ]
then
	opts="start stop restart"
fi

try() {
	eval $*
	if [ $? -ne 0 ]
	then
		echo 
		echo '!!! '"ERROR: the $1 command did not complete successfully."
		echo '!!! '"(\"${*}\")"
		echo '!!! '"Since this is a critical task, ebuild will be stopped."
		echo
		exit 1
	fi
}

needsme() {
	local x
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

ineed() {
	local x
	local z
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

#call this with "whoneeds" or "ineed" as first arg
query() {
	local deps
	local x
	install -d -m0755 ${svcdir}/depcheck/$$
	if [ "$1" = "ineed" ] && [ ! -L ${svcdir}/started/${myservice} ]
	then
			einfo "Warning: ${myservice} not running. need info may not be accurate."
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
	rm -rf ${svcdir}/depcheck/$$
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
	needsme|ineed)
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
		#add snapshot support here so any dependent services that
		#are stopped are restarted after the svc_start
		if [ -e ${svcdir}/started/${myservice} ]
		then
			svc_stop
			sleep 1
		fi
		svc_start
		;;
	*)
		echo "wrong args. (  $arg / $* )"
		usage $opts
		exit 1
		;;
	esac
done


