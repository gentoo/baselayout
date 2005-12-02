/*
 * debug.c
 *
 * Simle debugging/logging macro's and functions.
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
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "debug.h"

void debug_message (const char *file, const char *func, size_t line,
		    const char *format, ...)
{
  va_list arg;
  char *format_str;
  int length;

  save_errno ();
  
  length = strlen (format) + strlen ("DEBUG(2): ") + 1;
  /* Do not use xmalloc() here, else we may have recursive issues */
  format_str = malloc (length);
  if (NULL == format_str)
    {
      fprintf (stderr, "DEBUG(1): in %s, function %s(), line %i:\n", __FILE__,
	       __FUNCTION__, __LINE__);
      fprintf (stderr, "DEBUG(2): Failed to allocate buffer!\n");
      abort ();
    }

  snprintf (format_str, length, "DEBUG(2): %s", format);

  va_start (arg, format);
		
#if !defined(RC_DEBUG)
  /* Bit of a hack, as how we do things tend to cause seek
   * errors when reading the parent/child pipes */
  /* if ((0 != errno) && (ESPIPE != errno)) { */
  if (0 != errno)
    {
#endif
      fprintf (stderr, "DEBUG(1): in %s, function %s(), line %i:\n", __FILE__,
	       __FUNCTION__, __LINE__);
      vfprintf (stderr, format_str, arg);
      restore_errno ();
      
#if defined(RC_DEBUG)
      if (0 != errno)
	{
#endif
	  perror ("DEBUG(3)");
	  /* perror() for some reason sets errno to ESPIPE */
	  restore_errno ();
#if defined(RC_DEBUG)
	}
#else
    }
#endif

  va_end (arg);

  free (format_str);
}

void *__xmalloc (size_t size, const char *file, const char *func, size_t line)
{
  void *new_ptr;

  new_ptr = malloc (size);
  if (NULL == new_ptr)
    {
      /* Set errno in case specific malloc() implementation does not */
      errno = ENOMEM;
      
      debug_message (file, func, line, "Failed to allocate buffer!\n");
      
      return NULL;
    }

  return new_ptr;
}

void *__xrealloc (void *ptr, size_t size, const char *file, const char *func,
		  size_t line)
{
  void *new_ptr;

  new_ptr = realloc (ptr, size);
  if (NULL == new_ptr)
    {
      /* Set errno in case specific realloc() implementation does not */
      errno = ENOMEM;
      
      debug_message (file, func, line, "Failed to reallocate buffer!\n");
      
      return NULL;
    }

  return new_ptr;
}

