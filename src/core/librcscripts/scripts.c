/*
 * scripts.c
 *
 * Get info etc for Gentoo style rc-scripts.
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

LIST_HEAD (rcscript_list);

int
get_rcscripts (void)
{
  rcscript_info_t *info;
  char **file_list = NULL;
  char *rcscript;
  char *confd_file = NULL;
  int count;

  file_list = ls_dir (RCSCRIPTS_INITDDIR, 0);
  if (NULL == file_list)
    {
      errno = ENOENT;
      DBG_MSG ("'%s' is empty!\n", RCSCRIPTS_INITDDIR);
      return -1;
    }

  str_list_for_each_item (file_list, rcscript, count)
    {
      /* Is it a file? */
      if (!(is_file (rcscript, 1))
	  /* Do not process scripts, source or backup files. */
	  || (CHECK_FILE_EXTENSION (rcscript, ".c"))
	  || (CHECK_FILE_EXTENSION (rcscript, ".bak"))
	  || (CHECK_FILE_EXTENSION (rcscript, "~")))
	{
	  DBG_MSG ("'%s' is not a valid rc-script!\n", gbasename (rcscript));
	}
      else
	{
	  regex_data_t tmp_data;
	  char *buf = NULL;
	  char *tmp_buf = NULL;
	  size_t lenght;
	  int buf_count;
	  int current = 0;

	  if (-1 == file_map (rcscript, &buf, &lenght))
	    {
	      DBG_MSG ("Could not open '%s' for reading!\n",
		       gbasename (rcscript));
	      goto error;
	    }

	  buf_count = buf_get_line (buf, lenght, current);

	  tmp_buf = xstrndup (&(buf[current]), buf_count);
	  if (NULL == tmp_buf)
	    {
	      file_unmap (buf, lenght);
	      goto error;
	    }

	  file_unmap (buf, lenght);

	  /* Check if it starts with '#!/sbin/runscript' */
	  DO_REGEX (tmp_data, tmp_buf, "[ \t]*#![ \t]*/sbin/runscript[ \t]*.*",
		    check_error);
	  free (tmp_buf);
	  if (REGEX_FULL_MATCH != tmp_data.match)
	    {
	      DBG_MSG ("'%s' is not a valid rc-script!\n",
		       gbasename (rcscript));

	      continue;
	    }

	  /* We do not want rc-scripts ending in '.sh' */
	  if (CHECK_FILE_EXTENSION (rcscript, ".sh"))
	    {
	      EWARN ("'%s' is invalid (should not end with '.sh')!\n",
		     gbasename (rcscript));
	      continue;
	    }

	  DBG_MSG ("Adding rc-script '%s' to list.\n", gbasename (rcscript));

	  info = xmalloc (sizeof (rcscript_info_t));
	  if (NULL == info)
	    goto error;

	  /* Copy the name */
	  info->filename = xstrndup (rcscript, strlen (rcscript));
	  if (NULL == info->filename)
	    goto loop_error;

	  /* Get the modification time */
	  info->mtime = get_mtime (rcscript, 1);
	  if (0 == info->mtime)
	    {
	      DBG_MSG ("Failed to get modification time for '%s'!\n", rcscript);
	      /* We do not care if it fails - we will pick up
	       * later if there is a problem with the file */
	    }

	  /* File name for the conf.d config file (if any) */
	  confd_file = strcatpaths (RCSCRIPTS_CONFDDIR, gbasename (rcscript));
	  if (NULL == confd_file)
	    {
	      DBG_MSG ("Failed to allocate temporary buffer!\n");
	      goto loop_error;
	    }

	  /* Get the modification time of the conf.d file
	   * (if any exists) */
	  info->confd_mtime = get_mtime (confd_file, 1);
	  if (0 == info->confd_mtime)
	    {
	      DBG_MSG ("Failed to get modification time for '%s'!\n",
		       confd_file);
	      /* We do not care that it fails, as not all
	       * rc-scripts will have conf.d config files */
	    }

	  free (confd_file);

	  list_add_tail (&info->node, &rcscript_list);

	  continue;

check_error:
	  free (tmp_buf);
	  goto error;

loop_error:
	  if (NULL != info)
	    free (info->filename);
	  free (info);

	  goto error;
	}
    }

  /* Final check if we have some entries */
  if (!check_strv (file_list))
    {
      errno = ENOENT;
      DBG_MSG ("No rc-scripts to parse!\n");
      goto error;
    }

  str_list_free (file_list);

  return 0;

error:
  str_list_free (file_list);

  return -1;
}

/* Returns 0 if we do not need to regen the cache file, else -1 with
 * errno set if something went wrong */
int
check_rcscripts_mtime (const char *cachefile)
{
  rcscript_info_t *info;
  time_t cache_mtime;
  time_t rc_conf_mtime;
  time_t rc_confd_mtime;

  if (!check_arg_str (cachefile))
    return -1;

  cache_mtime = get_mtime (cachefile, 1);
  if (0 == cache_mtime)
    {
      DBG_MSG ("Could not get modification time for cache file '%s'!\n",
	       cachefile);
      return -1;
    }

  /* Get and compare mtime for RC_CONF_FILE_NAME with that of cachefile */
  rc_conf_mtime = get_mtime (RC_CONF_FILE_NAME, 1);
  if (rc_conf_mtime > cache_mtime)
    {
      DBG_MSG ("'%s' have a later modification time than '%s'.\n",
	       RC_CONF_FILE_NAME, cachefile);
      return -1;
    }
  /* Get and compare mtime for RC_CONFD_FILE_NAME with that of cachefile */
  rc_confd_mtime = get_mtime (RC_CONFD_FILE_NAME, 1);
  if (rc_confd_mtime > cache_mtime)
    {
      DBG_MSG ("'%s' have a later modification time than '%s'.\n",
	       RC_CONFD_FILE_NAME, cachefile);
      return -1;
    }

  /* Get and compare mtime for each rc-script and its conf.d config file
   * with that of cachefile */
  list_for_each_entry (info, &rcscript_list, node)
    {
      if ((info->mtime > cache_mtime) || (info->confd_mtime > cache_mtime))
	{
	  DBG_MSG ("'%s' have a later modification time than '%s'.\n",
		   info->filename, cachefile);
	  return -1;
	}
    }

  return 0;
}

rcscript_info_t *
get_rcscript_info (const char *scriptname)
{
  rcscript_info_t *info;

  if (!check_arg_str (scriptname))
    return NULL;

  list_for_each_entry (info, &rcscript_list, node)
    {
      if ((strlen (scriptname) == strlen (gbasename (info->filename)))
	  && (0 == strncmp (scriptname, gbasename (info->filename),
			    strlen (scriptname))))
	return info;
    }

  return NULL;
}

