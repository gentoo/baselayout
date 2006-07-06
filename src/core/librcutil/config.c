/*
 * misc.c
 *
 * Miscellaneous macro's and functions.
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
#include <string.h>
#include <stdlib.h>

#include "rcscripts/rcutil.h"

/* This handles simple 'entry="bar"' type variables.  If it is more complex
 * ('entry="$(pwd)"' or such), it will obviously not work, but current behaviour
 * should be fine for the type of variables we want. */
char *
rc_get_cnf_entry (const char *pathname, const char *entry, const char *sep)
{
  dyn_buf_t *dynbuf = NULL;
  char *buf = NULL;
  char *str_ptr;
  char *value = NULL;
  char *token;


  if ((!check_arg_str (pathname)) || (!check_arg_str (entry)))
    return NULL;

  /* If it is not a file or symlink pointing to a file, bail */
  if (!rc_is_file (pathname, TRUE))
    {
      errno = ENOENT;
      DBG_MSG ("'%s' is not a file or do not exist!\n", pathname);
      return NULL;
    }

  if (0 == rc_get_size (pathname, TRUE))
    {
      /* XXX: Should we set errno here ? */
      DBG_MSG ("'%s' have a size of 0!\n", pathname);
      return NULL;
    }

  dynbuf = new_dyn_buf_mmap_file (pathname);
  if (NULL == dynbuf)
    {
      DBG_MSG ("Could not open config file for reading!\n");
      return NULL;
    }

  while (NULL != (buf = read_line_dyn_buf (dynbuf)))
    {
      str_ptr = buf;

      /* Strip leading spaces/tabs */
      while ((str_ptr[0] == ' ') || (str_ptr[0] == '\t'))
	str_ptr++;

      /* Get entry and value */
      token = strsep (&str_ptr, "=");
      /* Bogus entry or value */
      if (NULL == token)
	goto _continue;

      /* Make sure we have a string that is larger than 'entry', and
       * the first part equals 'entry' */
      if ((strlen (token) > 0) && (0 == strcmp (entry, token)))
	{
	  do
	    {
	      /* Bash variables are usually quoted */
	      token = strsep (&str_ptr, "\"\'");
	      /* If quoted, the first match will be "" */
	    }
	  while ((NULL != token) && (0 == strlen (token)));

	  /* We have a 'entry='.  We respect bash rules, so NULL
	   * value for now (if not already) */
	  if (NULL == token)
	    {
	      /* We might have 'entry=' and later 'entry="bar"',
	       * so just continue for now ... we will handle
	       * it below when 'value == NULL' */
	      if ((!check_str(sep)) && (NULL != value))
		{
		  free (value);
		  value = NULL;
		}
	      goto _continue;
	    }

	  if ((!check_str(sep)) ||
	      ((check_str(sep)) && (NULL == value)))
	    {
	      /* If we have already allocated 'value', free it */
	      if (NULL != value)
		free (value);

	      value = xstrndup (token, strlen (token));
	      if (NULL == value)
		{
		  free_dyn_buf (dynbuf);
		  free (buf);

		  return NULL;
		}
	    }
	  else
	    {
	      value = xrealloc (value, strlen(value) + strlen(token) +
				strlen(sep) + 1);
	      if (NULL == value)
		{
		  free_dyn_buf (dynbuf);
		  free (buf);

		  return NULL;
		}
	      snprintf(value + strlen(value), strlen(token) + strlen(sep) + 1,
		       "%s%s", sep, token);
	    }

	  /* We do not break, as there might be more than one entry
	   * defined, and as bash uses the last, so should we */
	  /* break; */
	}

_continue:
      free (buf);
    }

  /* read_line_dyn_buf() returned NULL with errno set */
  if ((NULL == buf) && (0 != errno))
    {
      DBG_MSG ("Failed to read line from dynamic buffer!\n");
      free_dyn_buf (dynbuf);
      if (NULL != value)
	free (value);

      return NULL;
    }


  if (NULL == value)
    DBG_MSG ("Failed to get value for config entry '%s'!\n", entry);

  free_dyn_buf (dynbuf);

  return value;
}

char **
rc_get_list_file (char **list, char *filename)
{
  dyn_buf_t *dynbuf = NULL;
  char *buf = NULL;
  char *tmp_p = NULL;
  char *token = NULL;

  if (!check_arg_str (filename))
    return NULL;

  dynbuf = new_dyn_buf_mmap_file (filename);
  if (NULL == dynbuf)
    return NULL;

  while (NULL != (buf = read_line_dyn_buf (dynbuf)))
    {
      tmp_p = buf;

      /* Strip leading spaces/tabs */
      while ((tmp_p[0] == ' ') || (tmp_p[0] == '\t'))
	tmp_p++;

      /* Get entry - we do not want comments, and only the first word
       * on a line is valid */
      token = strsep (&tmp_p, "# \t");
      if (check_str (token))
	{
	  tmp_p = xstrndup (token, strlen (token));
	  if (NULL == tmp_p)
	    {
	      if (NULL != list)
		str_list_free (list);
	      free_dyn_buf (dynbuf);
	      free (buf);

	      return NULL;
	    }

	  str_list_add_item (list, tmp_p, error);
	}

      free (buf);
    }

  /* read_line_dyn_buf() returned NULL with errno set */
  if ((NULL == buf) && (0 != errno))
    {
      DBG_MSG ("Failed to read line from dynamic buffer!\n");
error:
      if (NULL != list)
	str_list_free (list);
      free_dyn_buf (dynbuf);

      return NULL;
    }

  free_dyn_buf (dynbuf);

  return list;
}
