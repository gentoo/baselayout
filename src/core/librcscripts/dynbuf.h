/*
 * dynbuf.h
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

#ifndef _DYNBUF_H
#define _DYNBUF_H

typedef struct {
  char *data;		/* Actual data */
  size_t length;	/* Length of data block */
  size_t rd_index;	/* Current read index */
  size_t wr_index;	/* Current write index */
} dynamic_buffer_t;

dynamic_buffer_t *new_dyn_buf (void);

void free_dyn_buf (dynamic_buffer_t *dynbuf);

int write_dyn_buf (dynamic_buffer_t *dynbuf, const char *buf, size_t length);

int sprintf_dyn_buf (dynamic_buffer_t *dynbuf, const char *format, ...);

int read_dyn_buf (dynamic_buffer_t *dynbuf, char *buf, size_t length);

#endif /* _DYNBUF_H */
