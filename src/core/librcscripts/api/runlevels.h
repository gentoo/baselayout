/*
 * runlevels.h
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

#ifndef _RUNLEVELS_H
#define _RUNLEVELS_H

typedef struct
{
  struct list_head node;

  char *dirname;		/* Name of this runlevel */
  struct list_head entries;	/* rcscript_info_t list of rc-scripts */
} runlevel_info_t;

struct list_head runlevel_list;

int get_runlevels (void);

runlevel_info_t * get_runlevel_info (const char *runlevel);

bool is_runlevel (const char *runlevel);

#endif /* _RUNLEVELS_H */
