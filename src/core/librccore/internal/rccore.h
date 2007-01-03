/*
 * rccore.h
 *
 * Internal Core includes.
 *
 * Copyright 2004-2007 Martin Schlemmer <azarah@nosferatu.za.org>
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

#ifndef __INTERNAL_RCCORE_H__
#define __INTERNAL_RCCORE_H__

#include "rcscripts/rccore.h"
#include "internal/services.h"

#include "librccore/api/scripts.h"
#include "librccore/api/runlevels.h"
#include "librccore/api/parse.h"
#include "librccore/api/depend.h"

#define RC_CONF_FILE_NAME	RCSCRIPTS_ETCDIR "/rc.conf"
#define RC_CONFD_FILE_NAME	RCSCRIPTS_CONFDDIR "/rc"

#define SVCDIR_CONFIG_ENTRY	"svcdir"

#define SBIN_RC			RCSCRIPTS_SBINDIR "/rc"
#define PROFILE_ENV		RCSCRIPTS_ETCDIR "/profile.env"

#define RCSCRIPT_HELP		RCSCRIPTS_LIBDIR "/sh/rc-help.sh"

#define DEFAULT_PATH		"PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/sbin"

#define SELINUX_LIB		RCSCRIPTS_LIBDIR "/runscript_selinux.so"

#define SYS_WHITELIST		RCSCRIPTS_LIBDIR "/conf.d/env_whitelist"
#define USR_WHITELIST		RCSCRIPTS_CONFDDIR "/env_whitelist"

#define SOFTLEVEL		"SOFTLEVEL"

/* Value of 'svcdir' in config files */
extern char *rc_config_svcdir;

#endif /* __INTERNAL_RCCORE_H__ */
