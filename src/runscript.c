/*
 * runscript.c
 * Handle launching of Gentoo init scripts.
 *
 * Copyright 1999-2004 Gentoo Foundation
 * Distributed under the terms of the GNU General Public License v2
 * $Header$
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <dlfcn.h>

#include "core/debug.h"
#include "core/misc.h"

#ifndef LIBDIR
# define LIBDIR		"lib"
#endif

#define SBIN_RC		"/sbin/rc"
#define PROFILE_ENV	"/etc/profile.env"
#define RCSCRIPTS_LIB	"/" LIBDIR "/rcscripts"
#define SYS_WHITELIST	RCSCRIPTS_LIB "/conf.d/env_whitelist"
#define USR_WHITELIST	"/etc/conf.d/env_whitelist"
#define RCSCRIPT_HELP	RCSCRIPTS_LIB "/sh/rc-help.sh"
#define SELINUX_LIB	RCSCRIPTS_LIB "/runscript_selinux.so"
#define SOFTLEVEL	"SOFTLEVEL"

#define DEFAULT_PATH	"PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/sbin"

#define IS_SBIN_RC()	(0 == strcmp(caller, SBIN_RC))

static void (*selinux_run_init_old) (void);
static void (*selinux_run_init_new) (int argc, char **argv);

extern char **environ;

void setup_selinux(int argc, char **argv) {
	void *lib_handle = NULL;
	
	lib_handle = dlopen(SELINUX_LIB, RTLD_NOW | RTLD_GLOBAL);
	if (NULL != lib_handle) {
		selinux_run_init_old = dlsym(lib_handle, "selinux_runscript");
		selinux_run_init_new = dlsym(lib_handle, "selinux_runscript2");

		/* Use new run_init if it exists, else fall back to old */
		if (NULL != selinux_run_init_new)
			selinux_run_init_new(argc, argv);
		else if (NULL != selinux_run_init_old)
			selinux_run_init_old();
		else {
			/* This shouldnt happen... probably corrupt lib */
			fprintf(stderr, "Run_init is missing from runscript_selinux.so!\n");
			exit(127);
		}
	}
}

char **get_whitelist(char **whitelist, char *filename) {
	char *buf = NULL;
	char *tmp_buf = NULL;
	char *tmp_p = NULL;
	char *token = NULL;
	size_t lenght = 0;
	int count = 0;
	int current = 0;
			
	if (-1 == file_map(filename, &buf, &lenght))
		return NULL;

	while (current < lenght) {
		count = buf_get_line(buf, lenght, current);

		tmp_buf = strndup(&buf[current], count);
		if (NULL == tmp_buf) {
			DBG_MSG("Failed to allocate temporary buffer!\n");
			goto error;
		}
		tmp_p = tmp_buf;
		
		/* Strip leading spaces/tabs */
		while ((tmp_p[0] == ' ') || (tmp_p[0] == '\t'))
			tmp_p++;

		/* Get entry - we do not want comments, and only the first word
		 * on a line is valid */
		token = strsep(&tmp_p, "# \t");
		if (NULL != token && '\0' != token[0]) {
			tmp_p = strndup(token, strlen(token));
			STRING_LIST_ADD(whitelist, tmp_p, error);
		}

		current += count + 1;
		free(tmp_buf);
		/* Set to NULL in case we error out above and have
		 * to free below */
		tmp_buf = NULL;
	}
				

	file_unmap(buf, lenght);

	return whitelist;

error:
	if (NULL != tmp_buf)
		free(tmp_buf);
	file_unmap(buf, lenght);
	STRING_LIST_FREE(whitelist);

	return NULL;
}

char **filter_environ(char *caller) {
	char **myenv = NULL;
	char **whitelist = NULL;
	char *env_name = NULL;
	int check_profile = 1;
	int count = 0;

	if (NULL != getenv(SOFTLEVEL) && !IS_SBIN_RC())
		/* Called from /sbin/rc, but not /sbin/rc itself, so current
		 * environment should be fine */
		return environ;

	if (1 == is_file(SYS_WHITELIST, 1))
		whitelist = get_whitelist(whitelist, SYS_WHITELIST);
	else
		EWARN("System environment whitelist missing!\n");

	if (1 == is_file(USR_WHITELIST, 1))
		whitelist = get_whitelist(whitelist, USR_WHITELIST);
	
	if (NULL == whitelist)
		/* If no whitelist is present, revert to old behaviour */
		return environ;
		
	if (1 != is_file(PROFILE_ENV, 1))
		/* XXX: Maybe warn here? */
		check_profile = 0;
	
	STRING_LIST_FOR_EACH(whitelist, env_name, count) {
		char *env_var = NULL;
		char *tmp_p = NULL;
		int env_len = 0;
	
		env_var = getenv(env_name);
		if (NULL != env_var)
			goto add_entry;

		if (1 == check_profile) {
			char *tmp_env_name = NULL;
			int tmp_len = 0;
			
			/* The entries in PROFILE_ENV is of the form:
			 * export VAR_NAME=value */
			tmp_len = strlen(env_name) + strlen("export ") + 1;
			tmp_env_name = calloc(tmp_len, sizeof(char *));
			if (NULL == tmp_env_name) {
				DBG_MSG("Failed to allocate temporary buffer!\n");
				goto error;
			}
			snprintf(tmp_env_name, tmp_len, "export %s", env_name);
			
			/* Clear errno so that subsequent calls do not trigger
			 * DBG_MSG */
			errno = 0;
			env_var = get_cnf_entry(PROFILE_ENV, tmp_env_name);
			free(tmp_env_name);
			if (NULL == env_var && ENOMSG != errno)
				goto error;
			else if (NULL != env_var)
				goto add_entry;
		}

		continue;
		
add_entry:
		env_len = strlen(env_name) + strlen(env_var) + 2;
		tmp_p = calloc(env_len, sizeof(char *));
		if (NULL == tmp_p) {
			DBG_MSG("Failed to allocate temporary buffer!\n");
			goto error;
		}
		snprintf(tmp_p, env_len, "%s=%s", env_name, env_var);
		STRING_LIST_ADD(myenv, tmp_p, error);
	}

	STRING_LIST_FREE(whitelist);

	if (NULL == myenv)
		/* If all else fails, just add a default PATH */
		STRING_LIST_ADD(myenv, strdup(DEFAULT_PATH), error);
	
	return myenv;

error:
	STRING_LIST_FREE(myenv);
	STRING_LIST_FREE(whitelist);
	
	return NULL;
}

int main(int argc, char *argv[]) {
	char *myargs[32];
	char **myenv = NULL;
	char *caller = argv[1];
	int new = 1;
	
	myargs[0] = "runscript";
	while (argv[new] != 0) {
		myargs[new] = argv[new];
		new++;
	}
	myargs[new] = NULL;

	/* Do not do help for /sbin/rc */
	if (argc < 3 && !IS_SBIN_RC()) {
		execv(RCSCRIPT_HELP, myargs);
		exit(1);
	}

	/* Setup a filtered environment according to the whitelist */
	myenv = filter_environ(caller);
	if (NULL == myenv) {
		EWARN("%s: Failed to filter the environment!\n", caller);
		/* XXX: Might think to bail here, but it could mean the system
		 *      is rendered unbootable, so rather not */
		myenv = environ;
	}

	/* Ok, we are ready to go, so setup selinux if applicable */
	setup_selinux(argc, argv);

	if (!IS_SBIN_RC()) {
		if (execve("/sbin/runscript.sh", myargs, myenv) < 0)
			exit(1);
	} else {
		if (execve("/bin/bash", myargs, myenv) < 0)
			exit(1);
	}

	return 0;
}
