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

#include <netdb.h>

#include "nss_service.h"

enum nss_status
_nss_service_gethostbyname2_r (const char *name, int af, struct hostent *result,
			       char *buffer, size_t buflen, int *errnop,
			       int *h_errnop)
{
  *h_errnop = HOST_NOT_FOUND;
  return _nss_service_status_e (errnop);
}

enum nss_status
_nss_service_gethostbyname_r (const char *name, struct hostent *result,
			      char *buffer, size_t buflen, int *errnop,
			      int *h_errnop)
{
  *h_errnop = HOST_NOT_FOUND;
  return _nss_service_status_e (errnop);
}

enum nss_status
_nss_service_gethostbyaddr_r (struct in_addr *addr, int len, int type,
			      struct hostent *result,
			      char *buffer, size_t buflen, int *errnop,
			      int *h_errnop)
{
  *h_errnop = HOST_NOT_FOUND;
  return _nss_service_status_e (errnop);
}

enum nss_status
_nss_service_sethostent (void)
{
  return _nss_service_status ();
}

enum nss_status
_nss_service_gethostent_r (struct hostent *result,
			   char *buffer, size_t buflen, int *errnop,
			   int *h_errnop)
{
  *h_errnop = HOST_NOT_FOUND;
  return _nss_service_status_e (errnop);
}

enum nss_status
_nss_service_endhostent (void)
{
  return NSS_STATUS_SUCCESS;
}

