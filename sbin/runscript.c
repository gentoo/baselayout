/*
 * Copyright 1999-2003 Gentoo Technologies, Inc.
 * Distributed under the terms of the GNU General Public License v2
 * $Header$
 */


#include <stdio.h>
#include <sys/types.h>
#include <wait.h>

int main(int argc, char **argv) {
	pid_t pid;
	char *myargs[32];
	int new=1;
	myargs[0]="runscript";
/*	if ( argc < 3 ) 
		exit(1);
*/
	while (argv[new]!=0) {
		myargs[new]=argv[new];
		new++; 
	}
	myargs[new]=(char *) 0;
	if ( argc < 3 ) {
		execv("/sbin/rc-help.sh",myargs);
		exit(1);
	}
	if (execv("/sbin/runscript.sh",myargs) < 0) 
		exit(1);
}
