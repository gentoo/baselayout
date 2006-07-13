/*
 * This file is part of nss_service.
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

#include <sys/types.h>

#include "nss_service.h"

enum nss_status
_nss_service_getautomntbyname_r (void *private, const char *key,
				 const char **canon_key, const char **value,
				 char *buffer, size_t buflen, int *errnop)
{
  return _nss_service_status_e (errnop);
}

enum nss_status
_nss_service_setautomntent (const char *mapname, void **private)
{
  return _nss_service_status ();
}

enum nss_status
_nss_service_getautomntent_r (void *private, const char **key, const char **val,
			      char *buffer, size_t buflen, int *errnop)
{
  return _nss_service_status_e (errnop);
}

enum nss_status
_nss_service_endautomntent (void **private)
{
  return NSS_STATUS_SUCCESS;
}

