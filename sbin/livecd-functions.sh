#!/bin/bash
# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2
# $Header$

# Global Variables:
#    CDBOOT			-- is booting off CD
#    LIVECD_CONSOLE		-- console that is specified to kernel commandline 
#				-- (ttyS0, tty1, etc). Only defined if passed to kernel
#    LIVECD_CONSOLE_BAUD	-- console baudrate specified
#    LIVECD_CONSOLE_PARITY	-- console parity specified
#    LIVECD_CONSOLE_DATABITS	-- console databits specified

livecd_parse_opt() {
	case "$1" in
		*\=*)
			echo "$1" | cut -f2 -d=;;
	esac
}

livecd_console_settings() {
	# scan for a valid baud rate
	case "$1" in
		300*)
			LIVECD_CONSOLE_BAUD=300
		;;
		600*)
			LIVECD_CONSOLE_BAUD=600
		;;
		1200*)
			LIVECD_CONSOLE_BAUD=1200
		;;
		2400*)
			LIVECD_CONSOLE_BAUD=2400
		;;
		4800*)
			LIVECD_CONSOLE_BAUD=4800
		;;
		9600*)
			LIVECD_CONSOLE_BAUD=9600
		;;
		14400*)
			LIVECD_CONSOLE_BAUD=14400
		;;
		19200*)
			LIVECD_CONSOLE_BAUD=19200
		;;
		28800*)
			LIVECD_CONSOLE_BAUD=28800
		;;
		38400*)
			LIVECD_CONSOLE_BAUD=38400
		;;
		57600*)
			LIVECD_CONSOLE_BAUD=57600
		;;
		115200*)
			LIVECD_CONSOLE_BAUD=115200
		;;
	esac
	if [ "${LIVECD_CONSOLE_BAUD}" = "" ]
	then
		# If it's a virtual console, set baud to 38400, if it's a serial
		# console, set it to 9600 (by default anyhow)
		case ${LIVECD_CONSOLE} in 
			tty[0-9])
				LIVECD_CONSOLE_BAUD=38400
			;;
			*)
				LIVECD_CONSOLE_BAUD=9600
			;;
		esac
	fi
	export LIVECD_CONSOLE_BAUD

	# scan for a valid parity
	# If the second to last byte is a [n,e,o] set parity
	local parity
	parity=`echo $1 | rev | cut -b 2-2`
	case "$parity" in
		[neo])
			LIVECD_CONSOLE_PARITY=$parity
		;;
	esac
	export LIVECD_CONSOLE_PARITY	

	# scan for databits
	# Only set databits if second to last character is parity
	if [ "${LIVECD_CONSOLE_PARITY}" != "" ]
	then
		LIVECD_CONSOLE_DATABITS=`echo $1 | rev | cut -b 1`
	fi
	export LIVECD_CONSOLE_DATABITS
	return 0
}


livecd_read_commandline() {
        local CMDLINE

# Line to be used for testing only. The formatting of the console=
# prompt can be found in /usr/src/linux/Documentation/serial-console.txt
# possible cmdline could look like this: CMDLINE="cdroot console=ttyS0,9600n8"

	CMDLINE=`cat /proc/cmdline`

	for x in ${CMDLINE}
	do
		case "${x}" in
			cdroot)
				CDBOOT="yes"
				export CDBOOT
			;;
			cdroot\=*)
				CDBOOT="yes"
				export CDBOOT
			;;
			console\=*)
				local live_console
				live_console=`livecd_parse_opt "${x}"`

				# Parse the console line. No options specified if
				# no comma
				LIVECD_CONSOLE=`echo ${live_console} | cut -f1 -d,`
				if [ "${LIVECD_CONSOLE}" = "" ]
				then
					# no options specified
					LIVECD_CONSOLE=${live_console}
				else
					# there are options, we need to parse them
					local livecd_console_opts
					livecd_console_opts=`echo ${live_console} | cut -f2 -d,`
					livecd_console_settings  ${livecd_console_opts}
				fi
				export LIVECD_CONSOLE
			;;
		esac
	done
	return 0
}


livecd_fix_inittab() {
	if [ "${CDBOOT}" = "" ]
	then
		return 1
	fi

	# Comment out current getty settings
	sed -i -e '/^c[0-9]/ s/^/#/' /etc/inittab

	# SPARC & HPPA console magic
	if [ "${HOSTTYPE}" = "sparc" -o "${HOSTTYPE}" = "hppa" -o "${HOSTTYPE}" = "ppc64" ]
	then
		# Mount openprom tree for user debugging purposes
		if [ "${HOSTTYPE}" = "sparc" ]
		then
			mount -t openpromfs none /proc/openprom
		fi

		# SPARC serial port A, HPPA mux / serial
		if [ -c "/dev/tts/0" ]
		then
			LIVECD_CONSOLE_BAUD=`stty -F /dev/tts/0 speed`
			echo "s0:12345:respawn:/sbin/agetty -nl /bin/bashlogin ${LIVECD_CONSOLE_BAUD} tts/0 vt100" >> /etc/inittab
		fi
		# HPPA software PDC console (K-models)
		if [ "${LIVECD_CONSOLE}" = "ttyB0" ]
		then
			mknod /dev/ttyB0 c 11 0
			LIVECD_CONSOLE_BAUD=`stty -F /dev/ttyB0 speed`
			echo "b0:12345:respawn:/sbin/agetty -nl /bin/bashlogin ${LIVECD_CONSOLE_BAUD} ttyB0 vt100" >> /etc/inittab
		fi
		# FB / STI console
		if [ -c "/dev/vc/1" ]
		then
			for x in 1 2 3 4 5 6
			do
				echo "c${x}:12345:respawn:/sbin/mingetty --noclear --autologin root tty${x}" >> /etc/inittab
			done
		fi
		if [ -c "/dev/hvc/0" ]
		then
			ln -s /dev/hvc/0 /dev/hvc0
			echo "c0:12345:respawn:/sbin/agetty -nl /bin/bashlogin 9600 hvc0 vt320" >> /etc/inittab
		fi
	# The rest...
	else
		if [ "${LIVECD_CONSOLE}" = "tty0" -o "${LIVECD_CONSOLE}" = "" ]
		then
			for x in 1 2 3 4 5 6
			do
				echo "c${x}:12345:respawn:/sbin/agetty -nl /bin/bashlogin 38400 tty${x} linux" >> /etc/inittab
			done	
		elif [ -c "/dev/hvc/0" ]
		then
			ln -s /dev/hvc/0 /dev/hvc0
			echo "c1:12345:respawn:/sbin/agetty -nl /bin/bashlogin 9600 hvc0 vt320" >> /etc/inittab
		else
			echo "c1:12345:respawn:/sbin/agetty -nl /bin/bashlogin ${LIVECD_CONSOLE_BAUD} ${LIVECD_CONSOLE} vt100" >> /etc/inittab
		fi
	fi
	return 0
}
