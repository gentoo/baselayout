#!/bin/bash
# Copyright 1999-2003 Gentoo Technologies, Inc.
# Distributed under the terms of the GNU General Public License v2
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
echo -e " Copyright 2001-2003 Gentoo Technologies, Inc.; Distributed under the GPL"
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
      'stop' to restart the service.  This is so that the dependencies
      can be handled correctly.  Refer to the portmap rc-script for an
      example.
	
EOHELP
echo -e "    ${GREEN}pause${OFF}"
cat <<EOHELP
      Same as 'stop', but the services that depends on it, will not be
      stopped.  This is useful for stopping a network interface without
      stopping all the network services that depend on 'net'.
	
EOHELP
echo -e "    ${GREEN}zap${OFF}"
cat <<EOHELP
      Reset a service that is currently stopped, but still marked as started,
      to the stopped state.  Basically for killing zombie services.

EOHELP
echo -e "    ${GREEN}status${OFF}"
cat <<EOHELP
      Prints "status:  started" if the service is running, else it
      prints "status:  stopped".

EOHELP
echo -e "    ${GREEN}ineed|iuse${OFF}"
cat <<EOHELP
      List the services this one depends on.  Consult the section about
      dependencies for more info on the different types of dependencies.

EOHELP
echo -e "    ${GREEN}needsme|usesme${OFF}"
cat <<EOHELP
      List the services that depend on this one.  Consult the section about
      dependencies for more info on the different types of dependencies.

EOHELP
echo -e "    ${GREEN}broken${OFF}"
cat <<EOHELP
      List the missing or broken dependencies of type 'need' this service
      depends on.

EOHELP
echo -e "${CYAN}Dependencies:${OFF}"
cat <<EOHELP
    This is the heart of the Gentoo RC-Scripts, as it determines the order
    in which services gets started, and also to some extend what services
    get started in the first place.

    The following example demonstrates how to use dependencies in
    rc-scripts:

    depend() {
        need foo bar
        use ray
    }

    Here we have foo and bar as dependencies of type 'need', and ray of
    type 'use'.  You can have as many dependencies of each type as needed, as 
    long as there is only one entry for each type, listing all its dependencies
    on one line only.
    
EOHELP
echo -e "    ${GREEN}need${OFF}"
cat <<EOHELP
      These are all the services needed for this service to start.  If any service
      in the 'need' line is not started, it will be started even if it is not
      in the current, or 'boot' runlevel, and then this service will be started.
      If any services in the 'need' line fails to start or is missing, this
      service will never be started.

EOHELP
echo -e "    ${GREEN}use${OFF}"
cat <<EOHELP
      This can be seen as representing optional services this service depends on
      that are not critical for it to start.  For any service in the 'use' line,
      it must be added to the 'boot' or current runlevel to be considered a valid
      'use' dependency.  It can also be used to determine startup order.

EOHELP
echo -e "    ${GREEN}before${OFF}"
cat <<EOHELP
      This, together with the 'after' dependency type, can be used to control
      startup order.  In core, 'before' and 'after' do not denote a dependency,
      but should be used for order changes that will only be honoured during
      a change of runlevel.  All services listed will get started *after* the
      current service.  In other words, this service will get started *before*
      all listed services.
            
EOHELP
echo -e "    ${GREEN}after${OFF}"
cat <<EOHELP
      All services listed will be started *before* the current service.  Have a
      look at 'before' for more info.
      
EOHELP
echo -e "    ${GREEN}provide${OFF}"
cat <<EOHELP
      This is not really a dependency type, rather it will enable you to create
      virtual services.  This is useful if there is more than one version of
      a specific service type, system loggers or crons for instance.  Just
      have each system logger provide 'logger', and make all services in need
      of a system logger depend on 'logger'.  This should make things much more
      generic.

EOHELP
cat <<EOHELP
    Note that the 'need', 'use', 'before' and 'after' dependeny types can have '*'
    as argument.  Having:
    
    depend() {
    	before *
    }
    
    will make the service start first in the current runlevel, and:
    
    depend() {
    	after *
    }
    
    will make the service the last to start.
    
    You should however be careful how you use this, as I really will not 
    recommend using it with the 'need' or 'use' dependency type ... you have
    been warned!

EOHELP
echo -e "${CYAN}'net' Dependency and 'net.*' Services:${OFF}"
cat <<EOHELP
    Example:

    depend() {
        need net
    }

    This is a special dependency of type 'need'.  It represents a state where
    a network interface or interfaces besides lo is up and active.  Any service
    starting with 'net.' will be treated as a part of the 'net' dependency, 
    if:

    1.  It is part of the 'boot' runlevel
    2.  It is part of the current runlevel

    A few examples are the /etc/init.d/net.eth0 and /etc/init.d/net.lo services.

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
