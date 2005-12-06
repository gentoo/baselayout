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

#include <errno.h>
#include <stddef.h>
#include <stdlib.h>
#include <string.h>

#include "rcscripts.h"

static char **get_runlevel_dirs (void);

LIST_HEAD (runlevel_list);

char **
get_runlevel_dirs (void)
{
  char **dir_list = NULL;
  char **runlvl_list = NULL;
  char *dir_item;
  int count;

  dir_list = ls_dir (RUNLEVELS_DIR, 0);
  if (NULL == dir_list)
    {
      errno = ENOENT;
      DBG_MSG ("Failed to get any entries in '%' !\n", RUNLEVELS_DIR);

      return NULL;
    }

  str_list_for_each_item (dir_list, dir_item, count)
    {
      if (is_dir (dir_item, 0))
	{
	  char *tmp_str;

	  tmp_str = xstrndup (dir_item, strlen (dir_item));
	  if (NULL == tmp_str)
	    goto error;

	  str_list_add_item (runlvl_list, tmp_str, error);
	}
    }

  str_list_free (dir_list);

  if (!check_strv (runlvl_list))
    {
      if (NULL != runlvl_list)
	str_list_free (runlvl_list);
    }

  return runlvl_list;

error:
  if (NULL != dir_list)
    str_list_free (dir_list);
  if (NULL != runlvl_list)
    str_list_free (runlvl_list);

  return NULL;
}

int
get_runlevels (void)
{
  char **runlvl_list = NULL;
  char *runlevel;
  int count;

  runlvl_list = get_runlevel_dirs ();
  if (NULL == runlvl_list)
    {
      DBG_MSG ("Failed to get any runlevels\n");

      return -1;
    }

  str_list_for_each_item (runlvl_list, runlevel, count)
    {
      runlevel_info_t *runlevel_info;
      char **dir_list = NULL;
      char *dir_item;
      int dir_count;

      DBG_MSG ("Adding runlevel '%s'\n", gbasename (runlevel));

      runlevel_info = xmalloc (sizeof (runlevel_info_t));
      if (NULL == runlevel_info)
	goto error;

      runlevel_info->dirname = xstrndup (runlevel, strlen (runlevel));
      if (NULL == runlevel_info->dirname)
	goto error;

      INIT_LIST_HEAD (&runlevel_info->entries);

      dir_list = ls_dir (runlevel, 0);
      if (NULL == dir_list)
	{
	  if (0 != errno)
	    goto error;

	  goto no_entries;
	}

      str_list_for_each_item (dir_list, dir_item, dir_count)
	{
	  rcscript_info_t *script_info;
	  rcscript_info_t *new_script_info = NULL;

	  if (!is_link (dir_item))
	    {
	      DBG_MSG ("Skipping non symlink '%s' !\n", dir_item);
	      continue;
	    }

	  script_info = get_rcscript_info (gbasename (dir_item));
	  if (NULL == script_info)
	    {
	      DBG_MSG ("Skipping invalid entry '%s' !\n", dir_item);
	      continue;
	    }

	  new_script_info = xmalloc (sizeof (rcscript_info_t));
	  if (NULL == new_script_info)
	    {
	      str_list_free (dir_list);
	      goto error;
	    }

	  DBG_MSG ("Adding '%s' to runlevel '%s'\n",
		   gbasename (script_info->filename),
		   gbasename (runlevel));

	  /* Add a copy, as the next and prev pointers will be changed */
	  memcpy (new_script_info, script_info, sizeof (rcscript_info_t));
	  list_add_tail (&new_script_info->node, &runlevel_info->entries);
	}

      str_list_free (dir_list);

no_entries:
      list_add_tail (&runlevel_info->node, &runlevel_list);
    }

  str_list_free (runlvl_list);

  return 0;

error:
  if (NULL != runlvl_list)
    str_list_free (runlvl_list);

  return -1;
}

runlevel_info_t *
get_runlevel_info (const char *runlevel)
{
  runlevel_info_t *info;

  if (!check_arg_str (runlevel))
    return NULL;

  list_for_each_entry (info, &runlevel_list, node)
    {
      if ((strlen (runlevel) == strlen (gbasename (info->dirname)))
	  && (0 == strncmp (runlevel, gbasename (info->dirname),
			    strlen (runlevel))))
	return info;
    }

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

