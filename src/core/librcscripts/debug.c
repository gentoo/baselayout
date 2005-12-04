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
#include "misc.h"

static char log_domain[] = "rcscripts";

void
debug_message (const char *file, const char *func, int line,
	       const char *format, ...)
{
  va_list arg;
  char *format_str;
  int length;

  save_errno ();

  length = strlen (log_domain) + strlen ("():       ") + 1;
  /* Do not use xmalloc() here, else we may have recursive issues */
  format_str = malloc (length);
  if (NULL == format_str)
    {
      fprintf (stderr, "(%s) error: in %s, function %s(), line %i:\n",
	       log_domain, __FILE__, __FUNCTION__, __LINE__);
      fprintf (stderr, "(%s)        Failed to allocate buffer!\n",
	       log_domain);
      abort ();
    }

  snprintf (format_str, length, "(%s)      ", log_domain);

  va_start (arg, format);

#if !defined(RC_DEBUG)
  /* Bit of a hack, as how we do things tend to cause seek
   * errors when reading the parent/child pipes */
  /* if ((0 != errno) && (ESPIPE != errno)) { */
  if (0 != saved_errno)
    {
#endif
      if (0 != saved_errno)
	fprintf (stderr, "(%s) error: ", log_domain);
      else
	fprintf (stderr, "(%s) debug: ", log_domain);

      fprintf (stderr, "in %s, function %s(), line %i:\n", file, func, line);

      fprintf (stderr, "%s  ", format_str);
      vfprintf (stderr, format, arg);

#if defined(RC_DEBUG)
      if (0 != saved_errno)
	{
#endif
	  perror (format_str);
#if defined(RC_DEBUG)
	}
#endif
#if !defined(RC_DEBUG)
    }
#endif

  va_end (arg);

  free (format_str);
  restore_errno ();
}

void *
__xcalloc(size_t nmemb, size_t size, const char *file,
	  const char *func, size_t line)
{
  void *new_ptr;

  new_ptr = calloc (nmemb, size);
  if (NULL == new_ptr)
    {
      /* Set errno in case specific malloc() implementation does not */
      errno = ENOMEM;

      debug_message (file, func, line, "Failed to allocate buffer!\n");

      return NULL;
    }

  return new_ptr;
}

void *
__xmalloc (size_t size, const char *file, const char *func, size_t line)
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

void *
__xrealloc (void *ptr, size_t size, const char *file,
	    const char *func, size_t line)
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

char *
__xstrndup (const char *str, size_t size, const char *file,
	    const char *func, size_t line)
{
  char *new_ptr;

  new_ptr = strndup (str, size);
  if (NULL == new_ptr)
    {
      /* Set errno in case specific realloc() implementation does not */
      errno = ENOMEM;

      debug_message (file, func, line,
		     "Failed to duplicate string via strndup() !\n");

      return NULL;
    }

  return new_ptr;
}

