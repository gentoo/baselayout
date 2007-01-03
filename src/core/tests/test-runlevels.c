/*
 * test-runlevels.c
 *
 * Test for runlevels functionality.
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

#include <stdlib.h>

#include "rcscripts/rccore.h"

#include "librccore/api/scripts.h"
#include "librccore/api/runlevels.h"
#include "librccore/api/parse.h"
#include "librccore/api/depend.h"

int
main (void)
{
  runlevel_info_t *runlevel_info;
  rcscript_info_t *script_info;
  
  if (-1 == get_rcscripts ())
    {
      EERROR ("Failed to get rc-scripts list!\n");
      exit (EXIT_FAILURE);
    }

  if (-1 == get_runlevels ())
    {
      EERROR ("Failed to get runlevel list!\n");
      exit (EXIT_FAILURE);
    }

#if 0
  EINFO ("Scripts:\n");

  list_for_each_entry (script_info, &rcscript_list, node)
    {
      printf ("  - %s\n", rc_basename (script_info->filename));
    }

  printf ("\n");
#endif

  list_for_each_entry (runlevel_info, &runlevel_list, node)
    {
      EINFO ("Runlevel %s:\n", rc_basename (runlevel_info->dirname));

      list_for_each_entry (script_info, &runlevel_info->entries, node)
	{
	  printf ("  - %s\n", rc_basename (script_info->filename));
	}
    }

  return 0;
}

