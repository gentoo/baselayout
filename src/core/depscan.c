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
 * $Header$
 */

#include <errno.h>
#include <locale.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <unistd.h>

#include "debug.h"
#include "depend.h"
#include "misc.h"
#include "parse.h"

char* svcdir_subdirs[] = {
	"softscripts",
	"snapshot",
	"options",
	"started",
	"starting",
	"inactive",
	"stopping",
	NULL
};

char *svcdir_volatile_subdirs[] = {
	"snapshot",
	"broken",
	NULL
};

int create_directory(const char *name);
int create_var_dirs(const char *svcdir);
int delete_var_dirs(const char *svcdir);

int create_directory(const char *name) {
	if ((NULL == name) || (0 == strlen(name))) {
		DBG_MSG("Invalid argument passed!\n");
		errno = EINVAL;
		return -1;
	}

	/* Check if directory exist, and is not a symlink */
	if (!is_dir(name, 0)) {
		if (exists(name)) {
			/* Remove it if not a directory */
			if (-1 == remove(name)) {
				DBG_MSG("Failed to remove '%s'!\n", name);
				return -1;
			}
		}
		/* Now try to create the directory */
		if (-1 == mktree(name, 0755)) {
			DBG_MSG("Failed to create '%s'!\n", name);
			return -1;
		}
	}

	return 0;
}

int create_var_dirs(const char *svcdir) {
	char *tmp_path = NULL;
	int i = 0;
	
	if ((NULL == svcdir) || (0 == strlen(svcdir))) {
		DBG_MSG("Invalid argument passed!\n");
		errno = EINVAL;
		return -1;
	}

	/* Check and create svcdir if needed */
	if (-1 == create_directory(svcdir)) {
		DBG_MSG("Failed to create '%s'!\n", svcdir);
		return -1;
	}

	while (NULL != svcdir_subdirs[i]) {
		tmp_path = strcatpaths(svcdir, svcdir_subdirs[i]);
		if (NULL == tmp_path) {
			DBG_MSG("Failed to allocate buffer!\n");
			return -1;
		}
		
		/* Check and create all the subdirs if needed */
		if (-1 == create_directory(tmp_path)) {
			DBG_MSG("Failed to create '%s'!\n", tmp_path);
			free(tmp_path);
			return -1;
		}
		
		free(tmp_path);
		i++;
	}

	return 0;
}

int delete_var_dirs(const char *svcdir) {
	char *tmp_path = NULL;
	int i = 0;
	
	if ((NULL == svcdir) || (0 == strlen(svcdir))) {
		DBG_MSG("Invalid argument passed!\n");
		errno = EINVAL;
		return -1;
	}

	/* Just quit if svcdir do not exist */
	if (!exists(svcdir)) {
		DBG_MSG("'%s' does not exist!\n", svcdir);
		return 0;
	}

	while (NULL != svcdir_volatile_subdirs[i]) {
		tmp_path = strcatpaths(svcdir, svcdir_volatile_subdirs[i]);
		if (NULL == tmp_path) {
			DBG_MSG("Failed to allocate buffer!\n");
			return -1;
		}

		/* Skip the directory if it does not exist */
		if (!exists(tmp_path))
			goto _continue;
		
		/* Check and delete all files and sub directories if needed */
		if (-1 == rmtree(tmp_path)) {
			DBG_MSG("Failed to delete '%s'!\n", tmp_path);
			free(tmp_path);
			return -1;
		}
		
_continue:
		free(tmp_path);
		i++;
	}

	return 0;
}

#if defined(LEGACY_DEPSCAN)

int main() {
	FILE *cachefile_fd = NULL;
	char *data = NULL;
	char *svcdir = NULL;
	char *cachefile = NULL;
	char *tmp_cachefile = NULL;
	int tmp_cachefile_fd = 0;
	int datasize = 0;

	/* Make sure we do not run into locale issues */
	setlocale (LC_ALL, "C");

	if (0 != getuid()) {
		EERROR("Must be root!\n");
		exit(EXIT_FAILURE);
	}

	svcdir = get_cnf_entry(RC_CONFD_FILE_NAME, SVCDIR_CONFIG_ENTRY);
	if (NULL == svcdir) {
		EERROR("Failed to get config entry '%s'!\n",
				SVCDIR_CONFIG_ENTRY);
		exit(EXIT_FAILURE);
	}

	/* Delete (if needed) volatile directories in svcdir */
	if (-1 == delete_var_dirs(svcdir)) {
		/* XXX: Not 100% accurate below message ... */
		EERROR("Failed to delete '%s', %s", svcdir,
				"or one of its sub directories!\n");
		exit(EXIT_FAILURE);
	}

	/* Create all needed directories in svcdir */
	if (-1 == create_var_dirs(svcdir)) {
		EERROR("Failed to create '%s', %s", svcdir,
				"or one of its sub directories!\n");
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
		EINFO("Caching service dependencies ...\n");
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

