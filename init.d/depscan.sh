#!/bin/bash

source /etc/init.d/functions.sh
svcdir=/dev/shm/.init.d

if [ ! -d $svcdir ]
then
	install -d -m0755 $svcdir
fi
for x in softscripts snapshot started need use
do
	if [ ! -d ${svcdir}/${x} ]
	then
		install -d -m0755 ${svcdir}/${x}
	fi
done

#call: depend_dbadd dep_type service deps....
depend_dbadd() {
	local mytype
	local myservice
	local x
	mytype=$1
	myservice=$2
	shift 2
	for x in $*
	do
		if [ ! -e /etc/init.d/${x} ]
		then
			#nice thing about use's, is that they do not have to exist
			if [ "$x" != "net" ] && [ "$mytype" != "use" ]
			then
			#bogus dependency
				einfo "need: can't find service \"${x}\" needed by \"${myservice}\"; continuing..."
				continue
			fi
		fi
		if [ ! -d ${svcdir}/${mytype}/${x} ]
		then
			install -d -m0755 ${svcdir}/${mytype}/${x}
		fi
		if [ ! -L ${svcdir}/${mytype}/${x}/${myservice} ]
		then
			ln -sf /etc/init.d/${myservice} ${svcdir}/${mytype}/${x}/${myservice}
		fi
	done
}

need() {
	NEED="$*"
}

use() {
	USE="$*"
}

ebegin "Caching service dependencies"
rm -rf ${svcdir}/need/*
rm -rf ${svcdir}/use/*
for x in /etc/runlevels/*/*
do
	if [ ! -L $x ]
	then
		continue
	fi

	#set to "" else we get problems
	NEED=""
	USE=""

	myservice=${x##*/}
	depend() {
		NEED=""
		USE=""
		return
	}
	source ${x}
	depend
	if [ "$NEED" = "" ] && [ "$USE" = "" ]
	then
		continue
	fi
	if [ "$NEED" != "" ]
	then
		depend_dbadd need $myservice $NEED
	fi
	if [ "$USE" != "" ]
	then
		depend_dbadd use $myservice $USE
	fi
done
eend
