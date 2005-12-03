/*
 * misc.h
 *
 * Miscellaneous macro's and functions.
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

#ifndef _MISC_H
#define _MISC_H

#include <sys/stat.h>
#include <sys/types.h>

/* Gentoo style e* printing macro's */
#define EINFO(_args...) \
 do { \
   int old_errno = errno; \
   printf(" \033[32;01m*\033[0m " _args); \
   errno = old_errno; \
 } while (0)

#define EWARN(_args...) \
 do { \
   int old_errno = errno; \
   printf(" \033[33;01m*\033[0m " _args); \
   errno = old_errno; \
 } while (0)

#define EERROR(_args...) \
 do { \
   int old_errno = errno; \
   fprintf(stderr, " \033[31;01m*\033[0m " _args); \
   errno = old_errno; \
 } while (0)

/* Min/Max macro's */
#ifdef MAX
#  undef MAX
#endif
#define MAX(_a, _b)	(((_a) > (_b)) ? (_a) : (_b))
#ifdef MIN
#  undef MIN
#endif
#define MIN(_a, _b)	((_a) > (_b) ? (_b) : (_a))

/* Return true if filename '_name' ends in '_ext' */
#define CHECK_FILE_EXTENSION(_name, _ext) \
 ((strlen(_name) > strlen(_ext)) \
  && (0 == strncmp(&(_name[strlen(_name) - strlen(_ext)]), \
		   _ext, strlen(_ext))))

/* Add a new item to a string list.  If the pointer to the list is NULL,
 * allocate enough memory for the amount of entries needed.  Ditto for
 * when it already exists, but we add one more entry than it can
 * contain.  The list is NULL terminated.
 * NOTE: _only_ memory for the list are allocated, and not for the items - that
 *       should be done by relevant code (unlike STRING_LIST_DEL that will
 *       free the memory) */
#define STRING_LIST_ADD(_string_list, _item, _error) \
 do { \
   char **_tmp_p; \
   int _i = 0; \
   if ((NULL == _item) || (0 == strlen(_item))) \
     { \
       DBG_MSG("Invalid argument passed!\n"); \
       errno = EINVAL; \
       goto _error; \
     } \
   while ((NULL != _string_list) && (NULL != _string_list[_i])) \
     { \
       _i++; \
     } \
   /* Amount of entries + new + terminator */ \
   _tmp_p = realloc(_string_list, sizeof(char *) * (_i + 2)); \
   if (NULL == _tmp_p) \
     { \
       DBG_MSG("Failed to reallocate list!\n"); \
       goto _error; \
     } \
   _string_list = _tmp_p; \
   _string_list[_i] = _item; \
   /* Terminator */ \
   _string_list[_i+1] = NULL; \
 } while (0)

/* Add a new item to a string list (foundamental the same as above), but make
 * sure we have all the items alphabetically sorted. */
#define STRING_LIST_ADD_SORT(_string_list, _item, _error) \
 do { \
   char **_tmp_p; \
   char *_str_p1; \
   char *_str_p2; \
   int _i = 0; \
   if ((NULL == _item) || (0 == strlen(_item))) \
     { \
       DBG_MSG("Invalid argument passed!\n"); \
       errno = EINVAL; \
       goto _error; \
     } \
   while ((NULL != _string_list) && (NULL != _string_list[_i])) \
     _i++; \
   /* Amount of entries + new + terminator */ \
   _tmp_p = realloc(_string_list, sizeof(char *) * (_i + 2)); \
   if (NULL == _tmp_p) \
     { \
       DBG_MSG("Failed to reallocate list!\n"); \
       goto _error; \
     } \
   _string_list = _tmp_p; \
   if (0 == _i) \
     /* Needed so that the end NULL will propagate
      * (iow, make sure our 'NULL != _str_p1' test below
      *  do not fail) */ \
     _string_list[_i] = NULL; \
   /* Actual terminator that needs adding */ \
   _string_list[_i+1] = NULL; \
   _i = 0; \
   /* See where we should insert the new item to have it all \
    * alphabetically sorted */ \
   while (NULL != _string_list[_i]) \
     { \
       if (strcmp(_string_list[_i], _item) > 0) \
	 { \
           break; \
         } \
       _i++; \
     } \
   /* Now just insert the new item, and shift the rest one over.
    * '_str_p2' is temporary storage to swap the indexes in a loop,
    * and 'str_p1' is used to store the old value across the loop */ \
   _str_p1 = _string_list[_i]; \
   _string_list[_i] = _item; \
    do { \
     _i++;\
     _str_p2 = _string_list[_i]; \
     _string_list[_i] = _str_p1; \
     _str_p1 = _str_p2; \
    } while (NULL != _str_p1); \
 } while (0)

/* Delete one entry from the string list, and shift the rest down if the entry
 * was not at the end.  For now we do not resize the amount of entries the
 * string list can contain, and free the memory for the matching item */
#define STRING_LIST_DEL(_string_list, _item, _error) \
 do { \
   int _i = 0; \
   if ((NULL == _item) \
       || (0 == strlen(_item)) \
       || (NULL == _string_list)) \
     { \
       DBG_MSG("Invalid argument passed!\n"); \
       errno = EINVAL; \
       goto _error; \
     } \
   while (NULL != _string_list[_i]) \
     { \
       if (0 == strcmp(_item, _string_list[_i])) \
         break; \
       else \
         _i++; \
     } \
   if (NULL == _string_list[_i]) \
     { \
       DBG_MSG("Invalid argument passed!\n"); \
       errno = EINVAL; \
       goto _error; \
     } \
   free(_string_list[_i]); \
   /* Shift all the following items one forward */ \
   do { \
     _string_list[_i] = _string_list[_i+1]; \
     /* This stupidity is to shutup gcc */ \
     _i++; \
   } while (NULL != _string_list[_i]); \
 } while (0)

/* Step through each entry in the string list, setting '_pos' to the
 * beginning of the entry.  '_counter' is used by the macro as index,
 * but should not be used by code as index (or if really needed, then
 * it should usually by +1 from what you expect, and should only be
 * used in the scope of the macro) */
#define STRING_LIST_FOR_EACH(_string_list, _pos, _counter) \
 if ((NULL != _string_list) && (0 == (_counter = 0))) \
   while (NULL != (_pos = _string_list[_counter++]))

/* Same as above (with the same warning about '_counter').  Now we just
 * have '_next' that are also used for indexing.  Once again rather refrain
 * from using it if not absolutely needed.  The major difference to above,
 * is that it should be safe from having the item removed from under you. */
#define STRING_LIST_FOR_EACH_SAFE(_string_list, _pos, _next, _counter) \
 if ((NULL != _string_list) && (0 == (_counter = 0))) \
   /* First part of the while checks if this is the
    * first loop, and if so setup _pos and _next
    * and increment _counter */ \
   while ((((0 == _counter) \
	    && (NULL != (_pos = _string_list[_counter])) \
	    && (_pos != (_next = _string_list[++_counter]))) \
	  /* Second part is when it is not the first loop
	   * and _pos was not removed from under us.  We
	   * just increment _counter, and setup _pos and
	   * _next */ \
	  || ((0 != _counter) \
	      && (_pos == _string_list[_counter-1]) \
	      && (_next == _string_list[_counter]) \
	      && (NULL != (_pos = _string_list[_counter])) \
	      && (_pos != (_next = _string_list[++_counter]))) \
	  /* Last part is when _pos was removed from under
	   * us.  We basically just setup _pos and _next,
	   * but leave _counter alone */ \
	  || ((0 != _counter) \
	      && (_pos != _string_list[_counter-1]) \
	      && (_next == _string_list[_counter-1]) \
	      && (NULL != (_pos = _string_list[_counter-1])) \
	      && (_pos != (_next = _string_list[_counter])))))

/* Just free the whole string list */
#define STRING_LIST_FREE(_string_list) \
 do { \
   if (NULL != _string_list) \
     { \
       int _i = 0; \
       while (NULL != _string_list[_i]) \
       free(_string_list[_i++]); \
       free(_string_list); \
       _string_list = NULL; \
     } \
 } while (0)

/* String functions.  Return a string on success, or NULL on error
 * or no action taken.  On error errno will be set.*/
char *memrepchr (char **str, char old, char _new, size_t size);
/* Concat two paths adding '/' if needed.  Memory will be allocated
 * with the malloc() call. */
char *strcatpaths (const char *pathname1, const char *pathname2);

/* Compat functions for GNU extensions */
#if !defined(HAVE_STRNDUP)
char *strndup (const char *str, size_t size);
#endif
/* Same as basename(3), but do not modify path */
char *gbasename (const char *path);

/* The following functions do not care about errors - they only return
 * 1 if 'pathname' exist, and is the type requested, or else 0.
 * They also might clear errno */
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
char *get_cnf_entry (const char *pathname, const char *entry);

/* Below three functions (file_map, file_unmap and buf_get_line) are from
 * udev-050 (udev_utils.c).  Please see misc.c for copyright info.
 * (Some are slightly modified, please check udev for originals.) */
int file_map (const char *filename, char **buf, size_t * bufsize);
void file_unmap (char *buf, size_t bufsize);
size_t buf_get_line (char *buf, size_t buflen, size_t cur);

#endif /* _MISC_H */
