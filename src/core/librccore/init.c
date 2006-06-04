/*
 * init.c
 *
 * Functions dealing with initialization.
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

#include <errno.h>
#include <stdlib.h>

char *rc_config_svcdir = NULL;

#include "internal/rccore.h"

static bool rc_initialized = FALSE;

int
rc_init (void)
{
  if (TRUE == rc_initialized)
    return 0;

  rc_config_svcdir = rc_get_cnf_entry (RC_CONFD_FILE_NAME, SVCDIR_CONFIG_ENTRY);
  if (NULL == rc_config_svcdir)
    {
      DBG_MSG ("Failed to get config entry '%s'!\n", SVCDIR_CONFIG_ENTRY);
      return -1;
    }

  rc_initialized = TRUE;

  return 0;
}

