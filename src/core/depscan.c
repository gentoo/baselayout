/*
 * depscan.c
 *
 * Basic frontend for updating the dependency cache.
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
 */

#include <errno.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "debug.h"
#include "depend.h"
#include "misc.h"
#include "parse.h"

#if defined(LEGACY_DEPSCAN)

int main() {
	FILE *cachefile_fd = NULL;
	char *data;
	char *svcdir = NULL;
	char *cachefile = NULL;
	char *tmp_cachefile = NULL;
	int tmp_cachefile_fd;
	int datasize;

	/* Make sure we do not run into locale issues */
	setlocale (LC_ALL, "C");
	
	svcdir = get_cnf_entry(RC_CONFD_FILE_NAME, SVCDIR_CONFIG_ENTRY);
	if (NULL == svcdir) {
		EERROR("Failed to get config entry '%s'!\n", SVCDIR_CONFIG_ENTRY);
		exit(EXIT_FAILURE);
	}
	
	cachefile = strcatpaths(svcdir, LEGACY_CACHE_FILE_NAME);
	if (NULL == cachefile) {
		DBG_MSG("Failed to allocate buffer!\n");
		exit(EXIT_FAILURE);
	}
	
	tmp_cachefile = strcatpaths(cachefile, "XXXXXX");
	if (NULL == tmp_cachefile) {
		DBG_MSG("Failed to allocate buffer!\n");
		exit(EXIT_FAILURE);
	}
	/* Replace the "/XXXXXX" with ".XXXXXX"
	 * Yes, I am lazy. */
	tmp_cachefile[strlen(tmp_cachefile) - strlen(".XXXXXX")] = '.';

	if (-1 == get_rcscripts()) {
		EERROR("Failed to get rc-scripts list!\n");
		exit(EXIT_FAILURE);
	}

	if (-1 == check_rcscripts_mtime(cachefile)) {
		DBG_MSG("Regenerating cache file '%s'.\n", cachefile);

		datasize = generate_stage2(&data);
		if (-1 == datasize) {
			EERROR("Failed to generate stage1!\n");
			exit(EXIT_FAILURE);
		}
		
		if (-1 == parse_cache(data, datasize)) {
			EERROR("Failed to generate stage2!\n");
			free(data);
			exit(EXIT_FAILURE);
		}

		free(data);

		if (-1 == service_resolve_dependencies()) {
			EERROR("Failed to resolve dependencies!\n");
			exit(EXIT_FAILURE);
		}

		tmp_cachefile_fd = mkstemp(tmp_cachefile);
		if (-1 == tmp_cachefile_fd) {
			EERROR("Could not open temporary file for writing!\n");
			exit(EXIT_FAILURE);
		}
		cachefile_fd = fdopen(tmp_cachefile_fd, "w");
		if (NULL == cachefile_fd) {
			EERROR("Could not open temporary file for writing!\n");
			exit(EXIT_FAILURE);
		}
		
		write_legacy_stage3(cachefile_fd);
		fclose(cachefile_fd);

		if ((-1 == remove(cachefile)) && (exists(cachefile))) {
			EERROR("Could not remove '%s'!\n", cachefile);
			remove(tmp_cachefile);
			exit(EXIT_FAILURE);
		}

		if (-1 == rename(tmp_cachefile, cachefile)) {
			EERROR("Could not move temporary file to '%s'!\n",
					cachefile);
			remove(tmp_cachefile);
			exit(EXIT_FAILURE);
		}
	}

	exit(EXIT_SUCCESS);
}

#endif

