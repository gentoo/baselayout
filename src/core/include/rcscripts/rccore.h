/*
 * rccore.h
 *
 * Core defines.
 *
 * Copyright (C) 2004-2006 Martin Schlemmer <azarah@nosferatu.za.org>
 *
 *
 *      This program is free software; you can redistribute it and/or modify it
 *      under the terms of the GNU General Public License as published by the
 *      Free Software Foundation version 2 of the License.
 *
 *      This program is distributed in the hope that it will be useful, but
 *      WITHOUT ANY WARRANTY; without even the implied warranty of
 *      MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *      General Public License for more details.
 *
 *      You should have received a copy of the GNU General Public License along
 *      with this program; if not, write to the Free Software Foundation, Inc.,
 *      675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * $Header$
 */

#ifndef __RCCORE_H__
#define __RCCORE_H__

#include "rcscripts/rcutil.h"
#include "librcscripts/api/scripts.h"
#include "librcscripts/api/runlevels.h"
#include "librcscripts/api/parse.h"
#include "librcscripts/api/depend.h"

#define RCSCRIPTS_CONFDDIR	ETCDIR "/conf.d"
#define RCSCRIPTS_INITDDIR	ETCDIR "/init.d"
#define RCSCRIPTS_LIBDIR	LIBDIR "/rcscripts"

#define RUNLEVELS_DIR		ETCDIR "/runlevels"

#define SBIN_RC			SBINDIR "/rc"
#define PROFILE_ENV		ETCDIR "/profile.env"

#define RC_CONF_FILE_NAME	ETCDIR "/rc.conf"
#define RC_CONFD_FILE_NAME	ETCDIR "/conf.d/rc"

#define RCSCRIPT_HELP		RCSCRIPTS_LIBDIR "/sh/rc-help.sh"

#define SVCDIR_CONFIG_ENTRY	"svcdir"

#define SHELL_PARSER		BINDIR "/bash"

#define DEFAULT_PATH		"PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/sbin"

#define SELINUX_LIB		RCSCRIPTS_LIBDIR "/runscript_selinux.so"

#define SYS_WHITELIST		RCSCRIPTS_LIBDIR "/conf.d/env_whitelist"
#define USR_WHITELIST		RCSCRIPTS_CONFDDIR "/env_whitelist"

#define SOFTLEVEL		"SOFTLEVEL"

#endif /* __RCCORE_H__ */
