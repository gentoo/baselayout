#!/bin/bash
# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License, v2 or later
# $Header$

source /etc/init.d/functions.sh

#dont quit too soon, else init will catch a respawn
x=10
while [ $x -ne 0 ]
do
	if [ -e ${svcdir}/options/xdm/service ]
	then
		exec "`cat ${svcdir}/options/xdm/service`" -nodaemon
		if [ $? -ne 0 ]
		then
			#there was a error running the DM, so return control to
			#init, so that it can catch any respawning
			einfo "ERROR: could not start the Display Manager..."
			continue
		fi
	else
		sleep 3
	fi
	x=$((x - 1))
done


