#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>

/* Define below to enable debugging messages */
#define RC_DEBUG

#define READ_PIPE 0
#define WRITE_PIPE 1

FILE *fopen_pipe(int pipefd, char *mode) {
        FILE *in_file;

        in_file = fdopen(pipefd, mode);
        NULL_PRINT_ERROR(in_file);

        return in_file;
}


int main() {
	char buf[80];
	/* server_pfds is used to send data to the server
	 * (thus the server only use the read pipe, and the
	 *  client uses the write pipe)
	 * client_pfds is used to send data to the client
	 * (thus the client only use the read pipe, and the
	 *  server uses the write pipe)
	 */
	int server_pfds[2], client_pfds[2];
	int retval, i, j;
	FILE *read_pipe, *write_pipe;
	pid_t child_pid;

	/* Pipe to send data to server */
	retval = pipe(server_pfds);
	NEG_PRINT_ERROR(retval);
	/* Pipe to send data to client */
	retval = pipe(client_pfds);
	NEG_PRINT_ERROR(retval);

#if 0
	/* Do not close pipes on exec */
	retval = fcntl(server_pfds[READ_PIPE], F_SETFD, 0);
	NEG_PRINT_ERROR(retval);
	retval = fcntl(server_pfds[WRITE_PIPE], F_SETFD, 0);
	NEG_PRINT_ERROR(retval);
	retval = fcntl(client_pfds[READ_PIPE], F_SETFD, 0);
	NEG_PRINT_ERROR(retval);
	retval = fcntl(client_pfds[WRITE_PIPE], F_SETFD, 0);
	NEG_PRINT_ERROR(retval);
#endif

	child_pid = fork();

	NEG_PRINT_ERROR(child_pid);

	if (0 == child_pid) {
		/***
		 ***   In child (client)
		 ***/

		char *const argv[] = { "bash", NULL };

		/* Close the sides of the pipes we do not use */
		close(client_pfds[WRITE_PIPE]); /* Only used for reading */
		close(server_pfds[READ_PIPE]); /* Only used for writing */

		/* Export the read/write descriptors to the environment */
		snprintf(buf, sizeof(buf) - 1, "%i", client_pfds[READ_PIPE]);
		retval = setenv("RC_READ_PIPE", buf, 1);
		NEG_PRINT_ERROR(retval);
		snprintf(buf, sizeof(buf) - 1, "%i", server_pfds[WRITE_PIPE]);
		retval = setenv("RC_WRITE_PIPE", buf, 1);
		NEG_PRINT_ERROR(retval);

		retval = execv("/bin/bash", argv);
		NEG_PRINT_ERROR(retval);
	} else {
		/***
		 ***   In parent (server)
		 ***/

		int tmp_pid;

		DBG_MSG("Child pid = %i\n", child_pid);

		/* Close the sides of the pipes we do not use */
		close(server_pfds[WRITE_PIPE]); /* Only used for reading */
		close(client_pfds[READ_PIPE]); /* Only used for writing */

		read_pipe = fopen_pipe(server_pfds[READ_PIPE], "r");
		write_pipe = fopen_pipe(client_pfds[WRITE_PIPE], "w");
		
		do {
			i = 0;

			do {
				j = fread(buf + i, 1, 1, read_pipe);
			} while(buf[i++] != '\n' && j > 0);
			
			buf[i] = '\0';

			if (i > 1) {
				DBG_MSG("Read = %s", buf);
				fwrite(buf, 1, strlen(buf), write_pipe);
				fflush(write_pipe);
			}
			
			tmp_pid = waitpid(child_pid, NULL, WNOHANG);
			DBG_MSG("tmp_pid = %i\n", tmp_pid);
		} while(0 != strncmp(buf, "quit", strlen("quit")) &&
			0 == tmp_pid);

		fclose(read_pipe);
		fclose(write_pipe);

		if (tmp_pid != child_pid) {
			DBG_MSG("Waiting for Child\n");
			if (-1 == waitpid(child_pid, NULL, 0))
				DBG_MSG("Child have already terminated!");
		}
	}

	return 0;
}

