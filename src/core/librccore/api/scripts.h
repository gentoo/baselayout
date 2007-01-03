/*
 * scripts.h
 *
 * Get info etc for Gentoo style rc-scripts.
 *
 * Copyright 2004-2007 Martin Schlemmer <azarah@nosferatu.za.org>
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

#ifndef __SCRIPTS_H__
#define __SCRIPTS_H__

typedef struct
{
  struct list_head node;

  char *filename;
  time_t mtime;
  time_t confd_mtime;
} rcscript_info_t;

struct list_head rcscript_list;

int get_rcscripts (void);
int check_rcscripts_mtime (const char *cachefile);
rcscript_info_t *get_rcscript_info (const char *scriptname);

#endif /* __SCRIPTS_H__ */
