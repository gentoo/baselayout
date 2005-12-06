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
#include <string.h>
#include <unistd.h>

#include "rcscripts.h"

static dyn_buf_t *reallocate_dyn_buf (dyn_buf_t * dynbuf, size_t needed);

dyn_buf_t *
new_dyn_buf (void)
{
  dyn_buf_t *dynbuf = NULL;

  dynbuf = xmalloc (sizeof (dyn_buf_t));
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
  dynbuf->file_map = FALSE;

  return dynbuf;
}

dyn_buf_t *
new_dyn_buf_from_file (const char *name)
{
  dyn_buf_t *dynbuf = NULL;

  dynbuf = xmalloc (sizeof (dyn_buf_t));
  if (NULL == dynbuf)
    return NULL;

  if (-1 == file_map (name, &dynbuf->data, &dynbuf->length))
    {
      DBG_MSG ("Failed to mmap file '%s'\n", name);
      free (dynbuf);
      
      return NULL;
    }

  dynbuf->wr_index = dynbuf->length;
  dynbuf->rd_index = 0;
  dynbuf->file_map = TRUE;

  return dynbuf;
}

dyn_buf_t *
reallocate_dyn_buf (dyn_buf_t * dynbuf, size_t needed)
{
  int len;

  if (!check_arg_dyn_buf (dynbuf))
    return NULL;

  if (dynbuf->file_map)
    {
      errno = EPERM;
      DBG_MSG ("Cannot reallocate mmap()'d file!\n");

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

void
free_dyn_buf (dyn_buf_t * dynbuf)
{
  if (NULL == dynbuf)
    return;

  if (!dynbuf->file_map)
    {
      if (NULL != dynbuf->data)
	{
	  free (dynbuf->data);
	  dynbuf->data = NULL;
	}
    }
  else
    {
      file_unmap (dynbuf->data, dynbuf->length);
    }

  dynbuf->length = 0;
  dynbuf->rd_index = 0;
  dynbuf->wr_index = 0;

  free (dynbuf);
  dynbuf = NULL;
}

int
write_dyn_buf (dyn_buf_t * dynbuf, const char *buf, size_t length)
{
  int len;

  if (!check_arg_dyn_buf (dynbuf))
    return -1;

  if (!check_arg_str (buf))
    return -1;

  if (dynbuf->file_map)
    {
      errno = EPERM;
      DBG_MSG ("Cannot write to readonly mmap()'d file!\n");

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

  if (0 < length)
    dynbuf->wr_index += length;

  if (-1 == length)
    DBG_MSG ("Failed to write to dynamic buffer!\n");

  return length;
}

int write_dyn_buf_from_fd (int fd, dyn_buf_t * dynbuf, size_t length)
{
  int len = length;

  if (!check_arg_dyn_buf (dynbuf))
    return -1;

  if (!check_arg_fd (fd))
    return -1;

  if (dynbuf->file_map)
    {
      errno = EPERM;
      DBG_MSG ("Cannot write to readonly mmap()'d file!\n");

      return -1;
    }

  if (NULL == reallocate_dyn_buf (dynbuf, length))
    {
      DBG_MSG ("Could not reallocate dynamic buffer!\n");
      return -1;
    }

  len = read (fd, (dynbuf->data + dynbuf->wr_index), len);

  if (length > len)
    length = len;

  if (0 < length)
    dynbuf->wr_index += length;

  dynbuf->data[dynbuf->wr_index] = '\0';

  if (-1 == length)
    DBG_MSG ("Failed to write to dynamic buffer!\n");

  return length;
}

int
sprintf_dyn_buf (dyn_buf_t * dynbuf, const char *format, ...)
{
  va_list arg1, arg2;
  char test_str[10];
  int needed, written = 0;

  if (!check_arg_dyn_buf (dynbuf))
    return -1;

  if (!check_arg_str (format))
    return -1;

  if (dynbuf->file_map)
    {
      errno = EPERM;
      DBG_MSG ("Cannot write to readonly mmap()'d file!\n");

      return -1;
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

  if (0 < written)
    dynbuf->wr_index += written;

  if (-1 == written)
    DBG_MSG ("Failed to write to dynamic buffer!\n");

  return written;
}

int
read_dyn_buf (dyn_buf_t * dynbuf, char *buf, size_t length)
{
  int len = length;

  if (!check_arg_dyn_buf (dynbuf))
    return -1;

  if (!check_arg_str (buf))
    return -1;

  if (dynbuf->rd_index >= dynbuf->length)
    return 0;

  if (dynbuf->wr_index < (dynbuf->rd_index + length))
    len = dynbuf->wr_index - dynbuf->rd_index;

  len = snprintf (buf, len + 1, "%s", (dynbuf->data + dynbuf->rd_index));

  /* If len is less than length, it means the string was shorter than
   * given length */
  if (length > len)
    length = len;

  if (0 < length)
    dynbuf->rd_index += length;

  if (-1 == length)
    DBG_MSG ("Failed to write from dynamic buffer!\n");

  return length;
}

int
read_dyn_buf_to_fd (int fd, dyn_buf_t * dynbuf, size_t length)
{
  int len = length;

  if (!check_arg_dyn_buf (dynbuf))
    return -1;

  if (!check_arg_fd (fd))
    return -1;

  if (dynbuf->rd_index >= dynbuf->length)
    return 0;

  if (dynbuf->wr_index < (dynbuf->rd_index + length))
    len = dynbuf->wr_index - dynbuf->rd_index;

  len = write (fd, (dynbuf->data + dynbuf->rd_index), len);
  if (length > len)
    length = len;

  if (0 < length)
    dynbuf->rd_index += length;

  if (-1 == length)
    DBG_MSG ("Failed to write from dynamic buffer!\n");

  return length;
}

char *
read_line_dyn_buf (dyn_buf_t *dynbuf)
{
  char *buf = NULL;
  size_t count = 0;

  if (!check_arg_dyn_buf (dynbuf))
    return NULL;

  for (count = dynbuf->rd_index; count < dynbuf->wr_index && dynbuf->data[count] != '\n'; count++);

  if (count > dynbuf->rd_index)
    {
      buf = xstrndup ((dynbuf->data + dynbuf->rd_index),
		      (count - dynbuf->rd_index));
      if (NULL == buf)
	return NULL;

      /* Also skip the '\n' .. */
      dynbuf->rd_index = count + 1;
    }

  return buf;
}

bool
dyn_buf_rd_eof (dyn_buf_t *dynbuf)
{
  if (!check_arg_dyn_buf (dynbuf))
    return FALSE;

  if (dynbuf->rd_index >= dynbuf->wr_index)
    return TRUE;

  return FALSE;
}

inline bool
check_dyn_buf (dyn_buf_t *dynbuf)
{
  if ((NULL == dynbuf) || (NULL == dynbuf->data) || (0 == dynbuf->length))
    return FALSE;

  return TRUE;
}

inline bool
__check_arg_dyn_buf (dyn_buf_t *dynbuf, const char *file, const char *func,
		 size_t line)
{
  if (!check_dyn_buf (dynbuf))
    {
      errno = EINVAL;

      debug_message (file, func, line, "Invalid dynamic buffer passed!\n");

      return FALSE;
    }

  return TRUE;
}

