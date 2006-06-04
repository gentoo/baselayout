/*
 * file.h
 *
 * Miscellaneous file related macro's and functions.
 *
 * Copyright (C) 2004-2006 Martin Schlemmer <azarah@nosferatu.za.org>
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

#ifndef __RC_FILE_H__
#define __RC_FILE_H__

#include <stdio.h>

/* Return true if filename '_name' ends in '_ext' */
#define CHECK_FILE_EXTENSION(_name, _ext) \
 ((check_str (_name)) && (check_str (_ext)) \
  && (strlen (_name) > strlen (_ext)) \
  && (0 == strncmp (&(_name[strlen(_name) - strlen(_ext)]), \
		    _ext, strlen(_ext))))

/* The following functions do not care about errors - they only return
 * 1 if 'pathname' exist, and is the type requested, or else 0.
 * This is only if pathname is valid ...  They also might clear errno */
int exists (const char *pathname);
int is_file (const char *pathname, int follow_link);
int is_link (const char *pathname);
int is_dir (const char *pathname, int follow_link);

/* The following function do not care about errors - it only returns
 * the mtime of 'pathname' if it exists, and is the type requested,
 * or else 0.  It also might clear errno */
time_t get_mtime (const char *pathname, int follow_link);

/* The following functions return 0 on success, or -1 with errno set on error. */
#if !defined(HAVE_REMOVE)
int remove (const char *pathname);
#endif
int mktree (const char *pathname, mode_t mode);
int rmtree (const char *pathname);

/* The following return a pointer on success, or NULL with errno set on error.
 * If it returned NULL, but errno is not set, then there was no error, but
 * there is nothing to return. */
char **ls_dir (const char *pathname, int hidden);

/* Below two functions (file_map, file_unmap and buf_get_line) are from
 * udev-050 (udev_utils.c).  Please see misc.c for copyright info.
 * (Some are slightly modified, please check udev for originals.) */
int file_map (const char *filename, char **buf, size_t * bufsize);
void file_unmap (char *buf, size_t bufsize);

#endif /* __RC_FILE_H__ */
