#include <stdio.h>
#include <sys/types.h>
#include <wait.h>

int main(int argc, char **argv) {
	pid_t pid;
	char *myargs[32];
	int new=1;
	myargs[0]="runscript";
	if ( argc < 3 ) 
		exit(1);
	while (argv[new]!=0) {
		myargs[new]=argv[new];
		new++; 
	}
	myargs[new]=(char *) 0;
	if (execv("/etc/init.d/runscript.sh",myargs) < 0) 
		exit(1);
}
