/*
 * Copyright 1999-2004 Gentoo Foundation
 * Distributed under the terms of the GNU General Public License v2
 * $Header$
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/types.h>
#include <wait.h>
#include <dlfcn.h>

static void (*selinux_run_init) (void);

int main(int argc, char **argv) {
	char *myargs[32];
	void *lib_handle;
	int new = 1;
	myargs[0] = "runscript";
	
/*	if (argc < 3)
		exit(1);
*/
	while (argv[new] != 0) {
		myargs[new] = argv[new];
		new++;
	}
	myargs[new] = (char *) 0;
	if (argc < 3) {
		execv("/lib/rcscripts/sh/rc-help.sh",myargs);
		exit(1);
	}
	
	lib_handle = dlopen("/lib/rcscripts/runscript_selinux.so", RTLD_LAZY | RTLD_GLOBAL);
	if( lib_handle != NULL ) {
		selinux_run_init = dlsym(lib_handle, "selinux_runscript");
		selinux_run_init();
	}

	if (execv("/sbin/runscript.sh",myargs) < 0)
		exit(1);

	return 0;
}
