#!/bin/bash
# Copyright 1999-2002 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License, v2 or later
# $Header$


source /etc/init.d/functions.sh

BLUE="\033[34;01m"
GREEN="\033[32;01m"
OFF="\033[0m"
CYAN="\033[36;01m"
				
myscript=${1}
if [ -L $1 ]
then
	myservice=`readlink ${1}`
else
	myservice=${1}
fi

myservice=${myservice##*/}

echo
echo -e "${GREEN}Gentoo Linux RC-Scripts; ${BLUE}http://www.gentoo.org/${OFF}"
echo -e " Copyright 2002 Gentoo Technologies, Inc.; Distributed under the GPL"
echo
echo -e "Usage: ${CYAN}${myservice}${OFF} [ ${GREEN}options${OFF} ]"
echo
echo -e "${CYAN}Options:${OFF}"
echo -e "    ${GREEN}start${OFF}"
cat <<EOHELP
      Start service, as well as the services it depends on (if not already
      started).
	
EOHELP
echo -e "    ${GREEN}stop${OFF}"
cat <<EOHELP
      Stop service, as well as the services that depend on it (if not already
      stopped).
	
EOHELP
echo -e "    ${GREEN}restart${OFF}"
cat <<EOHELP
      Restart service, as well as the services that depend on it.

      Note to developers:  If this function is replaced with a custom one,
      'svc_start' and 'svc_stop' should be used instead of 'start' and
      'stop' to restart the service.  This is so that the dependancies
      can be handled correctly.  Refer to the portmap rc-script for an
      example.
	
EOHELP
echo -e "    ${GREEN}pause${OFF}"
cat <<EOHELP
      Same as 'stop', but the services that depends on it, will not be
      stopped.  This is usefull for stopping a network interface without
      stopping all the network services that depend on 'net'.
	
EOHELP
echo -e "    ${GREEN}zap${OFF}"
cat <<EOHELP
      Reset a service that is currently stopped, but still marked as started,
      to the stopped state.  Basically for killing zombie services.

EOHELP
echo -e "    ${GREEN}ineed|iuse${OFF}"
cat <<EOHELP
      List the services this one depends on.  Consult the section about
      dependancies for more info on the different types of dependancies.

EOHELP
echo -e "    ${GREEN}needsme|usesme${OFF}"
cat <<EOHELP
      List the services that depends on this one.  Consult the section about
      dependancies for more info on the different types of dependancies.

EOHELP
echo -e "    ${GREEN}broken${OFF}"
cat <<EOHELP
      List the missing or broken dependancies of type 'need' this service
      depends on.

EOHELP
echo -e "${CYAN}Dependancies:${OFF}"
cat <<EOHELP
    This is the heart of the Gentoo RC-Scritps, as it determines the order
    in which services gets started, and also to some extend what services
    get started in the first place.

    The following example demonstrates how to use dependancies in
    rc-scripts:

    depend() {
        need foo bar
        use ray
    }

    Here we have foo and bar as dependancies of type 'need', and ray of
    type 'use'.  You can have as many dependancies of each type as needed, as 
    long as there is only one entry for each type, listing all its dependancies
    on one line only.
    
EOHELP
echo -e "    ${GREEN}need${OFF}"
cat <<EOHELP
      This is all the services needed for this service to start.  If any service
      in the 'need' line is not started, it will be started even if it is not
      in the current, or 'boot' runlevel, and then this service.  If any services
      in the 'need' line fails to start or is missing, this service will nerver
      get started.

EOHELP
echo -e "    ${GREEN}use${OFF}"
cat <<EOHELP
      This can be seen as optional services this service depends on, but is not
      critical for it to start.  For any service in the 'use' line, it must
      be added to the 'boot' or current runlevel to be considered a valid
      'use' dependancy.

EOHELP
echo -e "${CYAN}'net' Dependancy and 'net.*' Services:${OFF}"
cat <<EOHELP
    Example:

    depend() {
        need net
    }

    This is a special dependancy of type 'need'.  It represents a state where
    a network interface or interfaces besides lo is up and active.  Any service
    starting with 'net.' will be treated as a part of the 'net' dependancy, 
    if:

    1.  It is part of the 'boot' runlevel
    2.  It is part of the current runlevel

    A few examples is the /etc/init.d/net.eth0 and /etc/init.d/net.lo services.

EOHELP
echo -e "${CYAN}'logger' Dependancy:${OFF}"
cat <<EOHELP
    Example:

    depend() {
        use logger
    }

    This is a special dependancy of type 'use'.  It can be used for any service
    that needs a system logger running.
    
    As of writing, the logger target will include sysklogd, syslog-ng and
    metalog.  This can be overridden with the \$SYSLOGGER variable, which
    can be set either in /etc/rc.conf or /etc/conf.d/basic.

EOHELP
echo -e "${CYAN}Configuration files:${OFF}"
cat <<EOHELP
    There are three files which will be sourced for possible configuration by
    the rc-scripts.  They are (sourced from top to bottom):

    /etc/conf.d/basic
    /etc/conf.d/${myservice}
    /etc/rc.conf
    
EOHELP
echo -e "${CYAN}Management:${OFF}"
cat <<EOHELP
    Services are added and removed via the 'rc-update' tool.  Running it without
    arguments should give sufficient help.
    
EOHELP
