/*
 * depend.h
 *
 * Dependancy engine for Gentoo style rc-scripts.
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

#ifndef __DEPEND_H__
#define __DEPEND_H__

/* Dependency types supported or still to be implemented */
typedef enum
{
  NEED,				/* All dependencies needed by specified service */
  NEED_ME,			/* All dependencies that need specified service */
  USE,				/* All dependencies used by specified service */
  USE_ME,			/* All dependencies that use specified service */
  BEFORE,			/* All services started before specified service */
  AFTER,			/* All services started after specified service */
  BROKEN,			/* All dependencies of type NEED missing for
				   specified service */
  PROVIDE,			/* All virtual services provided by specified service */
  ALL_SERVICE_TYPE_T
} service_type_t;

/* Names for above service types (service_type_t).
 * Note that this should sync with above service_type_t */
extern char *service_type_names[];

typedef struct
{
  struct list_head node;

  char *name;			/* Name of service */
  char **depend_info[ALL_SERVICE_TYPE_T];	/* String lists for each service
						   type */
  char *provide;		/* Name of virtual service it
				   provides.  This is only valid
				   after we resolving - thus after
				   service_resolve_dependencies() */
  time_t mtime;			/* Modification time of script */
} service_info_t;

struct list_head service_info_list;

service_info_t *service_get_info (char *servicename);
int service_add (char *servicename);
int service_is_dependency (char *servicename, char *dependency,
			   service_type_t type);
int service_add_dependency (char *servicename, char *dependency,
			    service_type_t type);
int service_del_dependency (char *servicename, char *dependency,
			    service_type_t type);
service_info_t *service_get_virtual (char *virtual);
int service_add_virtual (char *servicename, char *virtual);
int service_set_mtime (char *servicename, time_t mtime);
int service_resolve_dependencies (void);

#endif /* __DEPEND_H__ */
