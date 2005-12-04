/*
 * runlevels.c
 *
 * Functions dealing with runlevels.
 *
 * Copyright (C) 2004,2005 Martin Schlemmer <azarah@nosferatu.za.org>
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

#include <stdlib.h>
#include <string.h>

#include "rcscripts.h"
#include "debug.h"
#include "misc.h"
#include "list.h"
#include "str_list.h"

static char ** get_runlevel_dirs (void);

LIST_HEAD (runlevel_list);

char **
get_runlevel_dirs (void)
{
  char **file_list = NULL;
  char **runlevel_list = NULL;
  char *file_item;
  int count;

  file_list = ls_dir (RUNLEVELS_DIR, 0);
  if (NULL == file_list)
    {
      errno = ENOENT;
      DBG_MSG ("Failed to get any entries in '%' !\n", RUNLEVELS_DIR);
      return NULL;
    }

  str_list_for_each_item (file_list, file_item, count)
    {
      if (is_dir (file_item, 0))
	{
	  char *tmp_str;

	  tmp_str = xstrndup (file_item, strlen (file_item));
	  if (NULL == tmp_str)
	    goto error;

	  str_list_add_item (runlevel_list, tmp_str, error);
	}
    }

  str_list_free (file_list);

  if ((NULL == runlevel_list) || (NULL == runlevel_list[0]))
    {
      errno = ENOENT;
      DBG_MSG ("Failed to get any runlevels!\n");
    }

  return runlevel_list;

error:
  if (NULL != file_list)
    str_list_free (file_list);
  if (NULL != runlevel_list)
    str_list_free (runlevel_list);
  
  return NULL;
}

bool
is_runlevel (const char *runlevel)
{
  char *runlevel_dir = NULL;
  int len;

  /* strlen (RUNLEVELS_DIR) + strlen (runlevel) + "/" + '\0' */
  len = strlen (RUNLEVELS_DIR) + strlen (runlevel) + 2;
  runlevel_dir = xmalloc (sizeof (char) * len);
  if (NULL == runlevel_dir)
    return FALSE;

  snprintf (runlevel_dir, len, "%s/%s", RUNLEVELS_DIR, runlevel);

  if (is_dir (runlevel_dir, 0))
    return TRUE;

  return FALSE;
}

