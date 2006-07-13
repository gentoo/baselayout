/*
 * This file is part of nss_service.
 * Copyright 2006 Roy Marples <roy@marples.name>
 *
 * nss_service is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * as published by the Free Software Foundation; either version 2.1 of
 * the License, or (at your option) any later version.
 *
 * nss_service is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with nss_service; if not, write to the Free
 * Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA
 * 02110-1301 USA
 */

#include <stdlib.h>
#include <string.h>

#include "nss_service.h"
#include "rcscripts/rccore.h"

static char *
_nss_service_get_cnf_entry (const char *filename, const char *entry)
{
  rc_dynbuf_t *dynbuf = NULL;
  char *buf = NULL;
  char *tmp_p = NULL;
  char *token = NULL;
  char *value = NULL;

  if (!check_arg_str (filename) && !check_arg_str (value))
    return NULL;

  dynbuf = rc_dynbuf_new_mmap_file (filename);
  if (NULL == dynbuf)
    return NULL;

  while (NULL != (buf = rc_dynbuf_read_line (dynbuf)))
    {
      tmp_p = buf;

      /* Strip leading whitespace */
      while ((tmp_p[0] == ' ') || (tmp_p[0] == '\t'))
	tmp_p++;

      token = strsep (&tmp_p, " \t");
      if (NULL == token)
	continue;

      if ((strlen(token) > 0) && (0 == strcmp (entry, token)))
	{
	  /* If we have already allocated 'value', free it */
	  if (NULL != value)
	    free (value);

	  value = xstrndup (tmp_p, strlen (tmp_p));
	}

      free (buf);

      if (NULL != value)
	break;
    }

  rc_dynbuf_free (dynbuf);
  
  return value;
}

enum nss_status
_nss_service_status (void)
{
  char *services = NULL;
  char *token = NULL;
  char *buf = _nss_service_get_cnf_entry (NSS_SERVICE_CONF_FILE,
					  NSS_SERVICE_SERVICES_ENTRY);
  enum nss_status retval = NSS_STATUS_NOTFOUND;

  if (NULL == buf)
    return retval;

  /* why do we need to reset errno? */
  errno = 0;
  rc_init ();

  services = buf;
  while (NULL != (token = strsep(&services, " ")))
    {
      /* If it's not a valid string, then it's also not a service */
      if (!check_str (token))
	continue;

      /* If any service is not started, stop checking and return */
      if (!rc_service_test_state (token, rc_service_started))
	{
	  retval = NSS_STATUS_UNAVAIL;
	  break;
	}
    }

  free (buf);

  return retval;
}

enum nss_status
_nss_service_status_e (int *errnop)
{
  *errnop = ENOENT;
  return _nss_service_status ();
}

