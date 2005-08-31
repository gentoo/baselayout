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
#include <sys/types.h>
#include <sys/wait.h>
#include <dlfcn.h>

static void (*selinux_run_init_old) (void);
static void (*selinux_run_init_new) (int argc, char **argv);

void setup_selinux(int argc, char **argv) {
	void *lib_handle;
	
	lib_handle = dlopen("/lib/rcscripts/runscript_selinux.so", RTLD_NOW | RTLD_GLOBAL);
	if (lib_handle != NULL) {
		selinux_run_init_old = dlsym(lib_handle, "selinux_runscript");
		selinux_run_init_new = dlsym(lib_handle, "selinux_runscript2");

		/* use new run_init if it exists, else fall back to old */
		if (selinux_run_init_new != NULL)
			selinux_run_init_new(argc, argv);
		else if (selinux_run_init_old != NULL)
			selinux_run_init_old();
		else {
			/* this shouldnt happen... probably corrupt lib */
			fprintf(stderr,"Run_init is missing from runscript_selinux.so!\n");
			exit(127);
		}
	}
}

int main(int argc, char *argv[]) {
	char *myargs[32];
	int new = 1;
	myargs[0] = "runscript";

	while (argv[new] != 0) {
		myargs[new] = argv[new];
		new++;
	}
	myargs[new] = NULL;
	if (argc < 3) {
		execv("/lib/rcscripts/sh/rc-help.sh", myargs);
		exit(1);
	}

	/* Ok, we are ready to go, so setup selinux if applicable */
	setup_selinux(argc, argv);

	if (execv("/sbin/runscript.sh", myargs) < 0)
		exit(1);

	return 0;
}
