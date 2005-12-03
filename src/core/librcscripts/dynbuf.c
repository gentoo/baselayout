/*
 * dynbuf.c
 *
 * Dynamic allocated buffers.
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

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

#include "debug.h"
#include "dynbuf.h"

#define DYNAMIC_BUFFER_SIZE (sizeof (char) * 2 * 1024)

static dynamic_buffer_t *reallocate_dyn_buf (dynamic_buffer_t *dynbuf,
					     size_t needed);

dynamic_buffer_t *new_dyn_buf (void)
{
  dynamic_buffer_t *dynbuf = NULL;

  dynbuf = xmalloc (sizeof (dynamic_buffer_t));
  if (NULL == dynbuf)
    return NULL;

  dynbuf->data = xmalloc (DYNAMIC_BUFFER_SIZE);
  if (NULL == dynbuf->data)
    {
      free (dynbuf);
      return NULL;
    }

  dynbuf->length = DYNAMIC_BUFFER_SIZE;
  dynbuf->rd_index = 0;
  dynbuf->wr_index = 0;

  return dynbuf;
}

dynamic_buffer_t *reallocate_dyn_buf (dynamic_buffer_t *dynbuf,
				      size_t needed)
{
  int len;

  if ((NULL == dynbuf) || (NULL == dynbuf->data) || (0 == dynbuf->length))
    {
      DBG_MSG ("Invalid dynamic buffer passed!\n");
      return NULL;
    }

  len = sizeof (char) * (dynbuf->wr_index + needed + 1);

  if (dynbuf->length < len)
    {
      char *new_ptr;

      /* Increase size in chunks to minimize reallocations */
      if (len < (dynbuf->length + DYNAMIC_BUFFER_SIZE))
	len = dynbuf->length + DYNAMIC_BUFFER_SIZE;

      new_ptr = xrealloc (dynbuf->data, len);
      if (NULL == new_ptr)
	return NULL;

      dynbuf->data = new_ptr;
      dynbuf->length = len;
    }

  return dynbuf;
}

void free_dyn_buf (dynamic_buffer_t *dynbuf)
{
  if (NULL == dynbuf)
    return;

  if (NULL != dynbuf->data)
    {
      free (dynbuf->data);
      dynbuf->data = NULL;
    }

  dynbuf->length = 0;
  dynbuf->rd_index = 0;
  dynbuf->wr_index = 0;

  free (dynbuf);
  dynbuf = NULL;
}

int write_dyn_buf (dynamic_buffer_t *dynbuf, const char *buf, size_t length)
{
  int len;

  if ((NULL == dynbuf) || (NULL == dynbuf->data) || (0 == dynbuf->length))
    {
      DBG_MSG ("Invalid dynamic buffer passed!\n");
      return 0;
    }

  if (NULL == buf)
    {
      DBG_MSG ("Invalid source buffer!\n");
      return -1;
    }

  if (NULL == reallocate_dyn_buf (dynbuf, length))
    {
      DBG_MSG ("Could not reallocate dynamic buffer!\n");
      return -1;
    }

  len = snprintf ((dynbuf->data + dynbuf->wr_index), length + 1, "%s", buf);
  /* If len is less than length, it means the string was shorter than
   * given length */
  if (length > len)
    length = len;

  dynbuf->wr_index += length;

  return length;
}

int sprintf_dyn_buf (dynamic_buffer_t *dynbuf, const char *format, ...)
{
  va_list arg1, arg2;
  char test_str[10];
  int needed, written = 0;

  if ((NULL == dynbuf) || (NULL == dynbuf->data) || (0 == dynbuf->length))
    {
      DBG_MSG ("Invalid dynamic buffer passed!\n");
      return 0;
    }

  va_start (arg1, format);
  va_copy (arg2, arg1);

  /* XXX: Lame way to try and figure out how much space we need */
  needed = vsnprintf (test_str, sizeof (test_str), format, arg2);
  va_end (arg2);

  if (NULL == reallocate_dyn_buf (dynbuf, needed))
    {
      DBG_MSG ("Could not reallocate dynamic buffer!\n");
      return -1;
    }

  written = vsnprintf ((dynbuf->data + dynbuf->wr_index), needed + 1,
		       format, arg1);
  va_end (arg1);

  dynbuf->wr_index += written;

  return written;
}

int read_dyn_buf (dynamic_buffer_t *dynbuf, char *buf, size_t length)
{
  int len = length;

  if ((NULL == dynbuf) || (NULL == dynbuf->data) || (0 == dynbuf->length))
    {
      DBG_MSG ("Invalid dynamic buffer passed!\n");
      return 0;
    }

  if (NULL == buf)
    {
      DBG_MSG ("Invalid destination buffer!\n");
      return -1;
    }

  if (dynbuf->rd_index >= dynbuf->length)
    return 0;

  if (dynbuf->length < (dynbuf->rd_index + length))
    len = dynbuf->length - dynbuf->rd_index;

  len = snprintf(buf, len + 1, "%s", (dynbuf->data + dynbuf->rd_index));
  /* If len is less than length, it means the string was shorter than
   * given length */
  if (length > len)
    length = len;

  dynbuf->rd_index += length;

  return length;
}

