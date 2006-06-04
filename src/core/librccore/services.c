/*
 * services.c
 *
 * Functions dealing with services.
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
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#include "internal/rccore.h"
#include "rcscripts/rccore.h"

char *rc_service_state_names[] = {
  "coldplugged",
  "starting",
  "started",
  "inactive",
  "wasinactive",
  "stopping",
  NULL
};

bool
rc_service_test_state (const char *service, rc_service_state_t state)
{
  char *state_dir;
  char *state_link;

  if (!check_str (service))
    return FALSE;

  if (exists (RC_SYSINIT_STATE))
    return FALSE;

  state_dir = strcatpaths (rc_config_svcdir, rc_service_state_names[state]);
  if (NULL == state_dir)
    {
      DBG_MSG ("Failed to allocate buffer!\n");
      return FALSE;
    }

  state_link = strcatpaths (state_dir, service);
  if (NULL == state_link)
    {
      free (state_dir);
      DBG_MSG ("Failed to allocate buffer!\n");
      return FALSE;
    }

  if (exists (state_link))
    {
      free (state_link);
      free (state_dir);
      return TRUE;
    }

  free (state_link);
  free (state_dir);

  return FALSE;
}

