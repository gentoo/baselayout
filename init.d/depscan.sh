#!/bin/bash

source /etc/init.d/functions.sh
svcdir=/dev/shm/.init.d

if [ ! -d $svcdir ]
then
	install -d -m0755 $svcdir
fi
for x in softscripts snapshot started need
do
	if [ ! -d ${svcdir}/${x} ]
	then
		install -d -m0755 ${svcdir}/${x}
	fi
done

need_dbadd() {
	local myservice
	local x
	myservice=$1
	shift
	for x in $*
	do
		local myneeded
#		if [ "$x" = "net" ]
#		then
#			myneeded=""
#			for y in ${svcdir}/softscripts/net.*
#			do
#				myneeded="$myneeded ${y##*/}"
#			done
#		else
		myneeded=${x}
#		fi
		for y in ${myneeded}
		do
			if [ ! -e /etc/init.d/${y} ]
			then
				if [ "$y" != "net" ]
				then
				#bogus dependency
					einfo "need: can't find service \"${y}\" needed by \"${myservice}\"; continuing..."
					continue
				fi
			fi
			if [ ! -d ${svcdir}/need/${y} ]
			then
				install -d -m0755 ${svcdir}/need/${y}
			fi
			if [ ! -L ${svcdir}/need/${y}/${myservice} ]
			then
				ln -s /etc/init.d/${myservice} ${svcdir}/need/${y}/${myservice}
			fi
		done
	done
}

need() {
	NEED="$*"
}

ebegin "Caching service dependencies"
rm -rf ${svcdir}/need/*
for x in /etc/runlevels/*/*
do
	if [ ! -L $x ]
	then
		continue
	fi
	myservice=${x##*/}
	depend() {
		NEED=""
		return	
	}
	source ${x}
	depend
	if [ "$NEED" = "" ]
	then
		continue
	fi
	need_dbadd $myservice $NEED
done
eend
