/*
 * depend.c
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

#include <errno.h>
#include <string.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>

#include "debug.h"
#include "depend.h"
#include "list.h"
#include "misc.h"

LIST_HEAD(service_info_list);

/* Names for service types (service_type_t) in depend.h.
 * Note that this should sync with service_type_t */
char *service_type_names[] = {
	"NEED",
	"NEED_ME",
	"USE",
	"USE_ME",
	"BEFORE",
	"AFTER",
	"BROKEN",
	"PROVIDE",
	NULL
};

int __service_resolve_dependency(char *servicename, char *dependency, service_type_t type);

service_info_t *service_get_info(char *servicename) {
	service_info_t *info;

	if ((NULL == servicename) || (0 == strlen(servicename))) {
		DBG_MSG("Invalid argument passed!\n");
		return NULL;
	}
	
	list_for_each_entry(info, &service_info_list, node) {
		if (NULL != info->name)
			if (0 == strcmp(info->name, servicename))
				return info;
	}

	/* We use this to check if a service exists, so rather do not
	 * add debugging, otherwise it is very noisy! */
	/* DBG_MSG("Invalid service name '%s'!\n", servicename); */
	
	return NULL;
}

int service_add(char *servicename) {
	service_info_t *info;
	service_info_t *sorted;
	int count;
	
	if ((NULL == servicename) || (0 == strlen(servicename))) {
		DBG_MSG("Invalid argument passed!\n");
		return -1;
	}

	info = service_get_info(servicename);
	if (NULL == info) {
		DBG_MSG("Adding service '%s'.\n", servicename);

		info = malloc(sizeof(service_info_t));
		if (NULL == info) {
			DBG_MSG("Failed to allocate service_info_t!\n");
			return -1;
		}

		info->name = strndup(servicename, strlen(servicename));
		if (NULL == info->name) {
			DBG_MSG("Failed to allocate buffer!\n");
			free(info);
			return -1;
		}

		for (count = 0; count < ALL_SERVICE_TYPE_T; count++)
			info->depend_info[count] = NULL;
		info->provide = NULL;
		/* -1 for now means unspecified.  If the service actually
		 * passed 'yes' or 'no', it will be 1 or 0, as we rather
		 * not assume about a service's parallel capabilities */
		info->parallel = -1;

		/* We want to keep the list sorted */
		list_for_each_entry(sorted, &service_info_list, node) {
			if (strcmp(sorted->name, servicename) > 0) {
				break;
			}
		}
		
		list_add_tail(&info->node, &sorted->node);
		
		return 0;
	} else {
		DBG_MSG("Tried to add duplicate service '%s'!\n", servicename);
	}
	
	return -1;
}

int service_is_dependency(char *servicename, char *dependency, service_type_t type) {
	service_info_t *info;
	char *service;
	int count = 0;
	
	if ((NULL == servicename) || (0 == strlen(servicename)) ||
	    (NULL == dependency) || (0 == strlen(dependency))) {
		DBG_MSG("Invalid argument passed!\n");
		return -1;
	}

	info = service_get_info(servicename);
	if (NULL != info) {
		STRING_LIST_FOR_EACH(info->depend_info[type], service, count) {
			if (0 == strcmp(dependency, service))
				return 0;
		}
	} else {
		DBG_MSG("Invalid service name '%s'!\n", servicename);
	}
	
	return -1;
}

int service_add_dependency(char *servicename, char *dependency, service_type_t type) {
	service_info_t *info;
	char *tmp_buf;
	
	if ((NULL == servicename) || (0 == strlen(servicename)) ||
	    (NULL == dependency) || (0 == strlen(dependency))) {
		DBG_MSG("Invalid argument passed!\n");
		return -1;
	}

	info = service_get_info(servicename);
	if (NULL != info) {
		/* Do not add duplicates */
		if (-1 == service_is_dependency(servicename, dependency, type)) {
			DBG_MSG("Adding dependency '%s' of service '%s', type '%s'.\n",
				dependency, servicename, service_type_names[type]);

			tmp_buf = strndup(dependency, strlen(dependency));
			if (NULL == tmp_buf) {
				DBG_MSG("Failed to allocate buffer!\n");
				return -1;
			}
			
			STRING_LIST_ADD_SORT(info->depend_info[type], tmp_buf, error);
		} else {
			DBG_MSG("Duplicate dependency '%s' for service '%s', type '%s'!\n",
					dependency, servicename,
					service_type_names[type]);
			/* Rather do not fail here, as we add a lot of doubles
			 * during resolving of dependencies */
		}

		return 0;
	} else {
		DBG_MSG("Invalid service name '%s'!\n", servicename);
	}
	
error:
	return -1;
}

int service_del_dependency(char *servicename, char *dependency, service_type_t type) {
	service_info_t *info;
	
	if ((NULL == servicename) || (0 == strlen(servicename)) ||
	    (NULL == dependency) || (0 == strlen(dependency))) {
		DBG_MSG("Invalid argument passed!\n");
		return -1;
	}

	if (-1 == service_is_dependency(servicename, dependency, type)) {
		DBG_MSG("Tried to remove invalid dependency '%s'!\n", dependency);
		return -1;
	}

	info = service_get_info(servicename);
	if (NULL != info) {
		DBG_MSG("Removing dependency '%s' of service '%s', type '%s'.\n",
			dependency , servicename, service_type_names[type]);

		STRING_LIST_DEL(info->depend_info[type], dependency, error);
		return 0;
	} else {
		DBG_MSG("Invalid service name '%s'!\n", servicename);
	}

error:
	return -1;
}

service_info_t *service_get_virtual(char *virtual) {
	service_info_t *info;
	
	if ((NULL == virtual) || (0 == strlen(virtual))) {
		DBG_MSG("Invalid argument passed!\n");
		return NULL;
	}
	
	list_for_each_entry(info, &service_info_list, node) {
		if (NULL != info->provide)
			if (0 == strcmp(info->provide, virtual))
				return info;
	}
	
	/* We use this to check if a virtual exists, so rather do not
	 * add debugging, otherwise it is very noisy! */
	/* DBG_MSG("Invalid service name '%s'!\n", virtual); */
	
	return NULL;
}

int service_add_virtual(char *servicename, char* virtual) {
	service_info_t *info;
	
	if ((NULL == servicename) || (0 == strlen(servicename)) ||
	    (NULL == virtual ) || (0 == strlen(virtual))) {
		DBG_MSG("Invalid argument passed!\n");
		return -1;
	}

	if (NULL != service_get_info(virtual)) {
		EERROR(" Cannot add provide '%s', as a service with the same name exists!\n",
				virtual);
		/* Do not fail here as we do have a service that resolves
		 * the virtual */
	}

	info = service_get_virtual(virtual);
	if (NULL != info) {
		/* We cannot have more than one service Providing a virtual */
		EWARN(" Service '%s' already provides '%s'!;\n",
				info->name, virtual);
		EWARN(" Not adding service '%s'...\n", servicename);
		/* Do not fail here as we do have a service that resolves
		 * the virtual */
	} else {
		info = service_get_info(servicename);
		if (NULL != info) {
			DBG_MSG("Adding virtual '%s' of service '%s'.\n",
					virtual, servicename);

			info->provide = strndup(virtual, strlen(virtual));
			if (NULL == info->provide) {
				DBG_MSG("Failed to allocate buffer!\n");
				return -1;
			}
		} else {
			DBG_MSG("Invalid service name '%s'!\n", servicename);
			return -1;
		}
	}

	return 0;
}

int service_set_mtime(char *servicename, time_t mtime) {
	service_info_t *info;

	if ((NULL == servicename) || (0 == strlen(servicename))) {
		DBG_MSG("Invalid argument passed!\n");
		return -1;
	}

	info = service_get_info(servicename);
	if (NULL != info) {
		DBG_MSG("Setting mtime '%li' of service '%s'.\n",
				mtime, servicename);
		
		info->mtime = mtime;

		return 0;
	} else {
		DBG_MSG("Invalid service name '%s'!\n", servicename);
	}
		
	return -1;
}

int service_set_parallel(char *servicename, char *parallel) {
	service_info_t *info;
	int status = 0;

	if ((NULL == servicename) || (0 == strlen(servicename)) ||
	    (NULL == parallel) || (0 == strlen(parallel))) {
		DBG_MSG("Invalid argument passed!\n");
		return -1;
	}

	if ((0 != strcmp(parallel, "yes")) && (0 != strcmp(parallel, "no"))) {
		EERROR(" The 'parallel' modifier can only take 'yes' or 'no' as argument!\n");
		EERROR(" Please fix this for the '%s' service.\n", servicename);
		return -1;
	}

	info = service_get_info(servicename);
	if (NULL != info) {
		DBG_MSG("Setting parallel to '%s' for service '%s'.\n",
				parallel, servicename);

		/* If 'yes', then parallel = 1, if 'no', then parallel = 0,
		 * else parallel = -1 as set by add_service() */
		if (0 == strcmp(parallel, "yes"))
			status = 1;
		
		info->parallel = status;

		return 0;
	} else {
		DBG_MSG("Invalid service name '%s'!\n", servicename);
	}
		
	return -1;
}

int __service_resolve_dependency(char *servicename, char *dependency, service_type_t type) {
	service_info_t *info;
	int retval;
	
	if ((NULL == servicename) || (0 == strlen(servicename)) ||
	    (NULL == dependency) || (0 == strlen(dependency))) {
		DBG_MSG("Invalid argument passed!\n");
		return -1;
	}

	info = service_get_info(servicename);
	if (NULL == info) {
		DBG_MSG("Invalid service name passed!\n");
		return -1;
	}

	DBG_MSG("Checking dependency '%s' of service '%s', type '%s'.\n",
			dependency, servicename, service_type_names[type]);

	/* If there are no existing service 'dependency', try to resolve
	 * possible virtual services */
	info = service_get_info(dependency);
	if (NULL == info) {
		info = service_get_virtual(dependency);
		if (NULL != info) {
			DBG_MSG("Virtual '%s' -> '%s' for service '%s', type '%s'.\n",
				dependency, info->name, servicename,
				service_type_names[type]);
		
			retval = service_del_dependency(servicename, dependency, type);
			if (-1 == retval) {
				DBG_MSG("Failed to delete dependency!\n");
				return -1;
			}
			
			/* Add the actual service name for the virtual */
			dependency = info->name;
			retval = service_add_dependency(servicename, dependency, type);
			if (-1 == retval) {
				DBG_MSG("Failed to add dependency!\n");
				return -1;
			}
		}
	}
	
	/* Handle 'need', as it is the only dependency type that should
	 * handle invalid database entries currently. */
	if (NULL == info) {
		if ((type == NEED) || (type == NEED_ME)) {
			EWARN(" Can't find service '%s' needed by '%s';  continuing...\n",
					dependency, servicename);

			retval = service_add_dependency(servicename, dependency, BROKEN);
			if (-1 == retval) {
				DBG_MSG("Failed to add dependency!\n");
				return -1;
			}

			/* Delete invalid entry */
			goto remove;
		}
		
		/* For the rest, if the dependency is not 'net', just silently
		 * die without error.  Should not be needed as we add a 'net'
		 * service manually before we start, but you never know ... */
		if (0 != strcmp(dependency, "net")) {
			/* Delete invalid entry */
			goto remove;
		}
	}

	/* Ugly bug ... if a service depends on itself, it creates a
	 * 'mini fork bomb' effect, and breaks things horribly ... */
	if (0 == strcmp(servicename, dependency)) {
		/* Dont work too well with the '*' before and after */
		if ((type != BEFORE) && (type != AFTER))
			EWARN(" Service '%s' can't depend on itself;  continuing...\n",
					servicename);

		/* Delete invalid entry */
		goto remove;
	}

	/* Currently only these depend/order types are supported */
	if ((type == NEED) || (type == USE) || (type == BEFORE) || (type == AFTER)) {
		if (type == BEFORE) {
			/* NEED and USE override BEFORE
			 * ('servicename' BEFORE 'dependency') */
			if ((0 == service_is_dependency(servicename, dependency, NEED)) ||
			    (0 == service_is_dependency(servicename, dependency, USE))) {
				/* Delete invalid entry */
				goto remove;
			}
		}

		if (type == AFTER) {
			/* NEED and USE override AFTER
			 * ('servicename' AFTER 'dependency') */
			if ((0 == service_is_dependency(dependency, servicename, NEED)) ||
			    (0 == service_is_dependency(dependency, servicename, USE))) {
				/* Delete invalid entry */
				goto remove;
			}
		}

		/* We do not want to add circular dependencies ... */
		if (0 == service_is_dependency(dependency, servicename, type)) {
			EWARN(" Services '%s' and '%s' have circular\n",
					servicename, dependency);
			EWARN(" dependency of type '%s';  continuing...\n",
					service_type_names[type]);

			/* For now remove this dependency */
			goto remove;
		}

		/* Reverse mapping */
		if (type == NEED) {
			retval = service_add_dependency(dependency, servicename, NEED_ME);
			if (-1 == retval) {
				DBG_MSG("Failed to add dependency!\n");
				return -1;
			}
		}

		/* Reverse mapping */
		if (type == USE) {
			retval = service_add_dependency(dependency, servicename, USE_ME);
			if (-1 == retval) {
				DBG_MSG("Failed to add dependency!\n");
				return -1;
			}
		}

		/* Reverse mapping */
		if (type == BEFORE) {
			retval = service_add_dependency(dependency, servicename, AFTER);
			if (-1 == retval) {
				DBG_MSG("Failed to add dependency!\n");
				return -1;
			}
		}

		/* Reverse mapping */
		if (type == AFTER) {
			retval = service_add_dependency(dependency, servicename, BEFORE);
			if (-1 == retval) {
				DBG_MSG("Failed to add dependency!\n");
				return -1;
			}
		}
	}

	return 0;
			
remove:		
	/* Delete invalid entry */
	DBG_MSG("Removing invalid dependency '%s' of service '%s', type '%s'.\n",
		dependency, servicename, service_type_names[type]);

	retval = service_del_dependency(servicename, dependency, type);
	if (-1 == retval) {
		DBG_MSG("Failed to delete dependency!\n");
		return -1;
	}

	/* Here we should not die with error */
	return 0;
}

int service_resolve_dependencies(void) {
	service_info_t *info;
	char *service;
	char *next = NULL;
	int count;

	/* Add our 'net' service */
	if (NULL == service_get_info("net")) {
		if (-1 == service_add("net"))
			return -1;
	}

	/* Calculate all virtuals */
	list_for_each_entry(info, &service_info_list, node) {
		STRING_LIST_FOR_EACH_SAFE(info->depend_info[PROVIDE], service, next, count)
				if (-1 == service_add_virtual(info->name, service)) {
					DBG_MSG("Failed to add virtual!\n");
					return -1;
				}
	}

	/* Now do NEED, USE, BEFORE and AFTER */
	list_for_each_entry(info, &service_info_list, node) {
		STRING_LIST_FOR_EACH_SAFE(info->depend_info[NEED], service, next, count) {
			if (-1 == __service_resolve_dependency(info->name, service, NEED)) {
				DBG_MSG("Failed to resolve dependency!\n");
				return -1;
			}
		}
	}
	list_for_each_entry(info, &service_info_list, node) {
		STRING_LIST_FOR_EACH_SAFE(info->depend_info[USE], service, next, count) {
			if (-1 == __service_resolve_dependency(info->name, service, USE)) {
				DBG_MSG("Failed to resolve dependency!\n");
				return -1;
			}
		}
	}
	list_for_each_entry(info, &service_info_list, node) {
		STRING_LIST_FOR_EACH_SAFE(info->depend_info[BEFORE], service, next, count) {
			if (-1 == __service_resolve_dependency(info->name, service, BEFORE)) {
				DBG_MSG("Failed to resolve dependency!\n");
				return -1;
			}
		}
	}
	list_for_each_entry(info, &service_info_list, node) {
		STRING_LIST_FOR_EACH_SAFE(info->depend_info[AFTER], service, next, count) {
			if (-1 == __service_resolve_dependency(info->name, service, AFTER)) {
				DBG_MSG("Failed to resolve dependency!\n");
				return -1;
			}
		}
	}

	return 0;
}

