/*
 * debug.h
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

#ifndef _DEBUG_H
#define _DEBUG_H

#if defined(RC_DEBUG)
# define DBG_MSG(_format, _arg...) \
	do { \
		int old_errno = errno; \
		fprintf(stderr, "DEBUG(1): in %s, function %s(), line %i:\n", __FILE__, \
				__FUNCTION__, __LINE__); \
		fprintf(stderr, "DEBUG(2): " _format, ## _arg); \
		errno = old_errno; \
		if (0 != errno) { \
			perror("DEBUG(3)"); \
			/* perror() for some reason sets errno to ESPIPE */ \
			errno = old_errno; \
		} \
	} while (0)
#else
# define DBG_MSG(_format, _arg...) \
	do { \
		int old_errno = errno; \
		/* Bit of a hack, as how we do things tend to cause seek
		 * errors when reading the parent/child pipes */ \
		/* if ((0 != errno) && (ESPIPE != errno)) { */ \
		if (0 != errno) { \
			fprintf(stderr, "DEBUG(1): in %s, function %s(), line %i:\n", \
					__FILE__, __FUNCTION__, __LINE__); \
			fprintf(stderr, "DEBUG(2): " _format, ## _arg); \
			errno = old_errno; \
			perror("DEBUG(3)"); \
			/* perror() for some reason sets errno to ESPIPE */ \
			errno = old_errno; \
		} \
	} while (0)
#endif

#define FATAL_ERROR() \
	do { \
		int old_errno = errno; \
		fprintf(stderr, "ERROR: file '%s', function '%s', line %i.\n", \
			__FILE__, __FUNCTION__, __LINE__); \
		errno = old_errno; \
		if (0 != errno) \
		 	perror("ERROR"); \
		exit(EXIT_FAILURE); \
	} while (0)

#define NEG_FATAL_ERROR(_x) \
	do { \
		if (-1 == _x) \
			FATAL_ERROR(); \
	} while (0)

#define NULL_FATAL_ERROR(_x) \
	do { \
		if (NULL == _x) \
			FATAL_ERROR(); \
	} while (0)

#endif /* _DEBUG_H */

