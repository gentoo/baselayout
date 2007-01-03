/*
 * test-services.c
 *
 * Test for services functionality.
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

int
main (int argc, char **argv)
{
  /* Needed to init config variables, etc! */
  rc_init ();

  if (argc >= 2)
    {
      if (rc_service_test_state (argv[1], rc_service_started))
	{
	  EINFO ("Service '%s': started\n", argv[1]);
	  exit (EXIT_SUCCESS);
	}
      else
	{
	  EERROR ("Service '%s': stopped\n", argv[1]);
	  exit (EXIT_FAILURE);
	}
    }

  return 0;
}

