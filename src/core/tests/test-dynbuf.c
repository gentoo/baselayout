/*
 * test-dynbuf.c
 *
 * Test for the dynamic buffer module.
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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "rcscripts/rcutil.h"

#define TEST_STRING1	 "Hello"
#define TEST_STRING2	 " "
#define TEST_STRING3	 "world"
#define TEST_STRING4	 "!\n"
#define TEST_STRING_FULL TEST_STRING1 TEST_STRING2 TEST_STRING3 TEST_STRING4

int
main (void)
{
  rc_dynbuf_t *dynbuf;
  char buf[1024 * 4];
  int length, total = 0;

  dynbuf = rc_dynbuf_new ();
  if (NULL == dynbuf)
    {
      fprintf (stderr, "Failed to allocate dynamic buffer.\n");
      return 1;
    }

  length = rc_dynbuf_sprintf (dynbuf, TEST_STRING1);
  if (length != strlen (TEST_STRING1))
    {
      fprintf (stderr, "rc_dynbuf_sprintf() returned wrong length (pass 1)!\n");
      goto error;
    }
  total += length;

  length = rc_dynbuf_write (dynbuf, TEST_STRING2, strlen (TEST_STRING2));
  if (length != strlen (TEST_STRING2))
    {
      fprintf (stderr, "rc_dynbuf_write() returned wrong length (pass 1)!\n");
      goto error;
    }
  total += length;

  length = rc_dynbuf_sprintf (dynbuf, TEST_STRING3);
  if (length != strlen (TEST_STRING3))
    {
      fprintf (stderr, "rc_dynbuf_sprintf() returned wrong length (pass 2)!\n");
      goto error;
    }
  total += length;

  length = rc_dynbuf_write (dynbuf, TEST_STRING4, strlen (TEST_STRING4));
  if (length != strlen (TEST_STRING4))
    {
      fprintf (stderr, "rc_dynbuf_write() returned wrong length (pass 2)!\n");
      goto error;
    }
  total += length;

  length = rc_dynbuf_read (dynbuf, buf, total / 2);
  if (length != total / 2)
    {
      fprintf (stderr, "rc_dynbuf_read() returned wrong length (pass 1)!\n");
      goto error;
    }

  length = rc_dynbuf_read (dynbuf, (buf + (total / 2)), total);
  if (length != (total - (total / 2)))
    {
      fprintf (stderr, "rc_dynbuf_read() returned wrong length (pass 2)!\n");
      goto error;
    }

  if (0 != strncmp (buf, TEST_STRING_FULL, strlen (TEST_STRING_FULL)))
    {
      fprintf (stderr, "Written and read strings differ!\n");
      goto error;
    }

  while (strlen (dynbuf->data) < 4096)
    {
      length = rc_dynbuf_sprintf (dynbuf, TEST_STRING_FULL);
      if (length != strlen (TEST_STRING_FULL))
	{
	  fprintf (stderr, "rc_dynbuf_sprintf() returned wrong length (%i)!\n",
		   (int)dynbuf->length);
	  goto error;
	}
      total += length;

      length = rc_dynbuf_write (dynbuf, TEST_STRING_FULL,
			      strlen (TEST_STRING_FULL));
      if (length != strlen (TEST_STRING_FULL))
	{
	  fprintf (stderr, "rc_dynbuf_write() returned wrong length (%i)!\n",
		   (int)dynbuf->length);
	  goto error;
	}
      total += length;
    }

  if (total != strlen (dynbuf->data))
    {
      fprintf (stderr, "Written string length should be %i, but is %i!\n",
	       total, (int)strlen (dynbuf->data));
      goto error;
    }

  rc_dynbuf_free (dynbuf);

  return 0;

error:
  rc_dynbuf_free (dynbuf);
  return 1;
}
