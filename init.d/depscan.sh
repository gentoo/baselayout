#!/bin/bash
# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License, v2 or later
# $Header$


source /etc/init.d/functions.sh

if [ ! -d $svcdir ]
then
	install -d -m0755 $svcdir
fi
for x in softscripts snapshot options broken started provide ${deptypes} ${ordtypes}
do
	if [ ! -d ${svcdir}/${x} ]
	then
		install -d -m0755 ${svcdir}/${x}
	fi
done

#call: depend_dbadd dep_type service deps....
depend_dbadd() {
	local mytype=$1
	local myservice=$2
	local x
	shift 2
	for x in $*
	do
		check_rcscript /etc/init.d/${x}
		local retval=$?
		if [ $retval -ne 0 ]
		then
			#handle 'need', as it is the only dependency type that
			#should handle invalid database entries currently.  The only
			#other type of interest is 'pretend' which *should* add
			#invalid database entries (no virtual depend should ever
			#actually have a matching rc-script).
			if [ "$mytype" = "need" ] && \
			   [ ! -d ${svcdir}/provide/${x} ] && \
			   [ "$x" != "net" ]
			then
				echo
				einfo "need: can't find service \"${x}\" needed by \"${myservice}\"; continuing..."
				
				#$myservice is broken due to missing 'need' dependancies
				if [ ! -d ${svcdir}/broken/${myservice} ]
				then
					install -d -m0755 ${svcdir}/broken/${myservice}
				fi
				if [ ! -e ${svcdir}/broken/${myservice}/${x} ]
				then
					touch ${svcdir}/broken/${myservice}/${x}
				fi
				continue
			elif [ "$mytype" != "provide" ] && \
			     [ ! -d ${svcdir}/provide/${x} ] && \
			     [ "$x" != "net" ]
			then
				continue
			fi
		fi

		#ugly bug ... if a service depends on itself, it creates
		#a 'mini fork bomb' effect, and breaks things...
		if [ "$x" = "$myservice" ]
		then
			#dont work too well with the '*' use and need
			if [ "$mytype" != "before" ] && [ "$mytype" != "after" ]
			then
				echo
				einfo "depend: service \"${x}\" can't depend on itself; continuing..."
			fi
			continue
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

check_rcscript() {
	[ ! -e $1 ] && return 1
	
	[ "${1##*.}" = "sh" ] && return 1
	[ "${1##*.}" = "c" ] && return 1

	local IFS='!'
	local hash shell
	(cat $1) | { read hash shell
        	if [ "$hash" = "#" ] && [ "$shell" = "/sbin/runscript" ]
		then
                	return 0
		else
			return 1
		fi
	}
}

need() {
	NEED="$*"
}

use() {
	USE="$*"
}

before() {
	BEFORE="$*"
}

after() {
	AFTER="$*"
}

provide() {
	PROVIDE="$*"
}

ebegin "Caching service dependencies"

#cleanup and fix a problem with 'for x in foo/*'
rm -rf ${svcdir}/need/*
touch ${svcdir}/need/dummy
rm -rf ${svcdir}/use/*
touch ${svcdir}/use/dummy
rm -rf ${svcdir}/before/*
touch ${svcdir}/before/dummy
rm -rf ${svcdir}/after/*
touch ${svcdir}/after/dummy
rm -rf ${svcdir}/broken/*
touch ${svcdir}/broken/dummy
rm -rf ${svcdir}/provide/*
touch ${svcdir}/provide/dummy

#for the '*' need and use types to work
oldpwd=`pwd`
cd /etc/init.d

#first calculate all the provides
for x in /etc/init.d/*
do
	check_rcscript $x || continue

	#set to "" else we get problems
	PROVIDE=""

	myservice=${x##*/}
	depend() {
		PROVIDE=""
		return
	}
	wrap_rcscript ${x} || {
		echo
		einfo "${x} has syntax errors in it, please fix this before trying"
		einfo "to execute this script..."
		einfo "NOTE: the dependancies for this script has not been calculated!"
		continue
	}
	depend
	if [ -n "$PROVIDE" ]
	then
		depend_dbadd provide $myservice $PROVIDE
	fi
done

#now do the rest
for x in /etc/init.d/*
do
	check_rcscript $x || continue

	#set to "" else we get problems
	NEED=""
	USE=""
	BEFORE=""
	AFTER=""

	myservice=${x##*/}
	depend() {
		NEED=""
		USE=""
		BEFORE=""
		AFTER=""
		return
	}
	#we already warn about the error in the provide loop
	wrap_rcscript ${x} || continue
	depend
	if [ -n "$NEED" ]
	then
		depend_dbadd need $myservice $NEED
	fi
	if [ -n "$USE" ]
	then
		depend_dbadd use $myservice $USE
	fi
	if [ -n "$BEFORE" ]
	then
		depend_dbadd before $myservice $BEFORE
		for x in $BEFORE
		do
			depend_dbadd after ${x} $myservice
		done
	fi
	if [ -n "$AFTER" ]
	then
		depend_dbadd after $myservice $AFTER
		for x in $AFTER
		do
			depend_dbadd before ${x} $myservice
		done
	fi
done

#resolve provides
for x in ${svcdir}/provide/*
do
	for mytype in ${deptypes}
	do
		if [ -d ${svcdir}/${mytype}/${x##*/} ]
		then
			for y in ${svcdir}/${mytype}/${x##*/}/*
			do
				depend_dbadd ${mytype} ${y##*/} `ls ${x}/`
			done
			rm -rf ${svcdir}/${mytype}/${x##*/}
		fi
	done

	counter=0
	for y in ${x}/*
	do
		counter=$((counter + 1))
		errstr="${x##*/}"
	done
done
if [ $counter -ne 1 ] && [ "${x##*/}" != "net" ]
then
	echo
	einfo "provide:  it usually is not a good idea to have more than one"
	einfo "          service providing the same virtual service (${errstr})!"
	cerror="yes"
fi

cd $oldpwd

eend


# vim:ts=4
