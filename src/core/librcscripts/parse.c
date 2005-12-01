/*
 * parse.c
 *
 * Parser for Gentoo style rc-scripts.
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
#include <string.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <signal.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/poll.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>

#include "rcscripts.h"
#include "debug.h"
#include "depend.h"
#include "list.h"
#include "misc.h"
#include "parse.h"
#include "simple-regex.h"

#define READ_PIPE			0
#define WRITE_PIPE			1

/* _pipe[0] is used to send data to the parent (thus the parent only use the
 * read pipe, and the child uses the write pipe)
 * _pipe[1] is used to send data to the child (thus the child only use the read
 * pipe, and the parent uses the write pipe)
 */
#define PARENT_READ_PIPE(_pipe)		(_pipe[0][READ_PIPE])
#define PARENT_WRITE_PIPE(_pipe)	(_pipe[1][WRITE_PIPE])
#define CHILD_READ_PIPE(_pipe)		(_pipe[1][READ_PIPE])
#define CHILD_WRITE_PIPE(_pipe)		(_pipe[0][WRITE_PIPE])

#define PARSE_BUFFER_SIZE		256

#define OUTPUT_MAX_LINE_LENGHT		256
#define OUTPUT_BUFFER_SIZE		(60 * 2048)

/* void PRINT_TO_BUFFER(char **_buf, int _count, label _error, format) */
#define PRINT_TO_BUFFER(_buf, _count, _error, _output...) \
	do { \
		int _i = 0; \
		/* FIXME: Might do something more dynamic here */ \
		if (OUTPUT_BUFFER_SIZE < (_count + OUTPUT_MAX_LINE_LENGHT)) { \
			errno = ENOMEM; \
			DBG_MSG("Output buffer size too small!\n"); \
			goto _error; \
		} \
		_i = sprintf(&((*_buf)[_count]), _output); \
		if (0 < _i) \
			_count += _i + 1; \
	} while (0)

LIST_HEAD(rcscript_list);

size_t parse_rcscript(char *scriptname, char **data, size_t index);

size_t parse_print_start(char **data, size_t index);
size_t parse_print_header(char *scriptname, char **data, size_t index);
size_t parse_print_body(char *scriptname, char **data, size_t index);

int get_rcscripts(void)
{
	rcscript_info_t *info;
	char **file_list = NULL;
	char *rcscript;
	char *confd_file = NULL;
	int count;

	file_list = ls_dir(RCSCRIPTS_INITDDIR, 0);
	if (NULL == file_list) {
		DBG_MSG("'%s' is empty!\n", RCSCRIPTS_INITDDIR);
		return -1;
	}

	STRING_LIST_FOR_EACH(file_list, rcscript, count) {
		    /* Is it a file? */
		if (!(is_file(rcscript, 1))
		    /* Do not process scripts, source or backup files. */
		    || (CHECK_FILE_EXTENSION(rcscript, ".c"))
		    || (CHECK_FILE_EXTENSION(rcscript, ".bak"))
		    || (CHECK_FILE_EXTENSION(rcscript, "~"))) {
			DBG_MSG("'%s' is not a valid rc-script!\n",
			        gbasename(rcscript));
		} else {
			DBG_MSG("Adding rc-script '%s' to list.\n",
			        gbasename(rcscript));

			info = malloc(sizeof(rcscript_info_t));
			if (NULL == info) {
				DBG_MSG("Failed to allocate rcscript_info_t!\n");
				goto error;
			}

			/* Copy the name */
			info->filename = strndup(rcscript, strlen(rcscript));
			if (NULL == info->filename) {
				DBG_MSG("Failed to allocate buffer!\n");
				goto loop_error;
			}

			/* Get the modification time */
			info->mtime = get_mtime(rcscript, 1);
			if (0 == info->mtime) {
				DBG_MSG("Failed to get modification time for '%s'!\n",
				        rcscript);
				/* We do not care if it fails - we will pick up
				 * later if there is a problem with the file */
			}

			/* File name for the conf.d config file (if any) */
			confd_file = strcatpaths(RCSCRIPTS_CONFDDIR, gbasename(rcscript));
			if (NULL == confd_file) {
				DBG_MSG("Failed to allocate temporary buffer!\n");
				goto loop_error;
			}
			
			/* Get the modification time of the conf.d file
			 * (if any exists) */
			info->confd_mtime = get_mtime(confd_file, 1);
			if (0 == info->confd_mtime) {
				DBG_MSG("Failed to get modification time for '%s'!\n",
				        confd_file);
				/* We do not care that it fails, as not all
				 * rc-scripts will have conf.d config files */
			}
			
			free(confd_file);

			list_add_tail(&info->node, &rcscript_list);

			continue;
			
loop_error:
			if (NULL != info)
				free(info->filename);
			free(info);
			
			goto error;
		}
	}

	/* Final check if we have some entries */
	if ((NULL == file_list) || (NULL == file_list[0])) {
		DBG_MSG("No rc-scripts to parse!\n");
		errno = ENOENT;
		goto error;
	}

	STRING_LIST_FREE(file_list);

	return 0;

error:
	STRING_LIST_FREE(file_list);

	return -1;
}

/* Returns 0 if we do not need to regen the cache file, else -1 with
 * errno set if something went wrong */
int check_rcscripts_mtime(char *cachefile)
{
	rcscript_info_t *info;
	time_t cache_mtime;
	time_t rc_conf_mtime;
	time_t rc_confd_mtime;

	if ((NULL == cachefile) || (0 == strlen(cachefile))) {
		DBG_MSG("Invalid argument passed!\n");
		errno = EINVAL;
		return -1;
	}
	
	cache_mtime = get_mtime(cachefile, 1);
	if (0 == cache_mtime) {
		DBG_MSG("Could not get modification time for cache file '%s'!\n",
		        cachefile);
		return -1;
	}

	/* Get and compare mtime for RC_CONF_FILE_NAME with that of cachefile */
	rc_conf_mtime = get_mtime(RC_CONF_FILE_NAME, 1);
	if (rc_conf_mtime > cache_mtime) {
		DBG_MSG("'%s' have a later modification time than '%s'.\n",
		        RC_CONF_FILE_NAME, cachefile);
		return -1;
	}
	/* Get and compare mtime for RC_CONFD_FILE_NAME with that of cachefile */
	rc_confd_mtime = get_mtime(RC_CONFD_FILE_NAME, 1);
	if (rc_confd_mtime > cache_mtime) {
		DBG_MSG("'%s' have a later modification time than '%s'.\n",
		        RC_CONFD_FILE_NAME, cachefile);
		return -1;
	}

	/* Get and compare mtime for each rc-script and its conf.d config file
	 * with that of cachefile */
	list_for_each_entry(info, &rcscript_list, node) {
		if ((info->mtime > cache_mtime)
		    || (info->confd_mtime > cache_mtime)) {
			DBG_MSG("'%s' have a later modification time than '%s'.\n",
			        info->filename, cachefile);
			return -1;
		}
	}
	
	return 0;
}

/* Return count on success, -1 on error.  If it was critical, errno will be set. */
size_t parse_rcscript(char *scriptname, char **data, size_t index)
{
	regex_data_t tmp_data;
	char *buf = NULL;
	char *tmp_buf = NULL;
	size_t write_count = index;
	size_t lenght;
	int count;
	int current = 0;

	if ((NULL == scriptname) || (0 == strlen(scriptname))) {
		DBG_MSG("Invalid argument passed!\n");
		errno = EINVAL;
		return -1;
	}
	
	if (-1 == file_map(scriptname, &buf, &lenght)) {
		DBG_MSG("Could not open '%s' for reading!\n",
		        gbasename(scriptname));
		return -1;
	}
	
	while (current < lenght) {
		count = buf_get_line(buf, lenght, current);

		tmp_buf = strndup(&(buf[current]), count);
		if (NULL == tmp_buf) {
			DBG_MSG("Failed to allocate temporary buffer!\n");
			goto error;
		}

		if (0 == current) {
			/* Check if it starts with '#!/sbin/runscript' */
			DO_REGEX(tmp_data, tmp_buf,
			         "[ \t]*#![ \t]*/sbin/runscript[ \t]*.*", error);
			if (REGEX_FULL_MATCH != tmp_data.match) {
				DBG_MSG("'%s' is not a valid rc-script!\n",
				        gbasename(scriptname));
				goto error;
			}

			/* We do not want rc-scripts ending in '.sh' */
			if (CHECK_FILE_EXTENSION(scriptname, ".sh")) {
				EWARN("'%s' is invalid (should not end with '.sh')!\n",
				      gbasename(scriptname));
				goto error;
			}
			DBG_MSG("Parsing '%s'.\n", gbasename(scriptname));

			write_count = parse_print_header(gbasename(scriptname),
			                                 data, write_count);
			if (-1 == write_count) {
				DBG_MSG("Failed to call parse_print_header()!\n");
				goto error;
			}

			goto _continue;
		}
		
		/* Check for lines with comments, and skip them */
		DO_REGEX(tmp_data, tmp_buf, "^[ \t]*#", error);
		if (REGEX_MATCH(tmp_data))
			goto _continue;

		/* If the line contains 'depend()', set 'got_depend' */
		DO_REGEX(tmp_data, tmp_buf, "depend[ \t]*()[ \t]*{?", error);
		if (REGEX_MATCH(tmp_data)) {
			DBG_MSG("Got 'depend()' function.\n");

			write_count = parse_print_body(gbasename(scriptname),
			                               data, write_count);
			if (-1 == write_count) {
				DBG_MSG("Failed to call parse_print_body()!\n");
				goto error;
			}

			/* Make sure this is the last loop */
			current += lenght;
			goto _continue;
		}
	
_continue:
		current += count + 1;
		free(tmp_buf);
	}

	file_unmap(buf, lenght);
	
	return write_count;

error:
	free(tmp_buf);
	if (NULL != buf) {
		int old_errno = errno;
		file_unmap(buf, lenght);
		/* file_unmap() might have changed it */
		errno = old_errno;
	}

	return -1;
}


size_t generate_stage1(char **data)
{
	rcscript_info_t *info;
	size_t write_count = 0;
	size_t tmp_count;

	write_count = parse_print_start(data, write_count);
	if (-1 == write_count) {
		DBG_MSG("Failed to call parse_print_start()!\n");
		return -1;
	}

	list_for_each_entry(info, &rcscript_list, node) {
		tmp_count = parse_rcscript(info->filename, data, write_count);
		if (-1 == tmp_count) {
			DBG_MSG("Failed to parse '%s'!\n",
			        gbasename(info->filename));

			/* If 'errno' is set, it is critical (hopefully) */
			if (0 != errno)
				return -1;
		} else {
			write_count = tmp_count;
		}
	}
		
	return write_count;
}

/* Empty signal handler for SIGPIPE */
static void sig_handler(int signum)
{
	return;
}

/* Returns data's lenght on success, else -1 on error. */
size_t generate_stage2(char **data)
{
	int pipe_fds[2][2] = { { 0, 0 }, { 0, 0 } };
	pid_t child_pid;
	size_t write_count = 0;
	int old_errno = 0;

	/* Pipe to send data to parent */
	if (-1 == pipe(pipe_fds[0])) {
		DBG_MSG("Failed to open pipe!\n");
		goto error;
	}
	/* Pipe to send data to child */
	if (-1 == pipe(pipe_fds[1])) {
		DBG_MSG("Failed to open pipe!\n");
		/* Close parent_pfds */
		goto error;
	}

	/* Zero data */
	*data = NULL;

	child_pid = fork();
	if (-1 == child_pid) {
		DBG_MSG("Failed to fork()!\n");
		/* Close all pipes */
		goto error;
	}
	if (0 == child_pid) {
		/***
		 ***   In child
		 ***/

		char *const argv[] = {
			"bash",
			"--noprofile",
			"--norc",
			"--",
			NULL
		};

		/* Close the sides of the pipes we do not use */
		close(PARENT_WRITE_PIPE(pipe_fds));
		close(PARENT_READ_PIPE(pipe_fds));

		/* dup2 child side read pipe to STDIN */
		dup2(CHILD_READ_PIPE(pipe_fds), STDIN_FILENO);
		/* dup2 child side write pipe to STDOUT */
		dup2(CHILD_WRITE_PIPE(pipe_fds), STDOUT_FILENO);

		/* We need to be in RCSCRIPTS_INITDDIR for 'before'/'after' '*' to work */
		if (-1 == chdir(RCSCRIPTS_INITDDIR)) {
			DBG_MSG("Failed to chdir to '%s'!\n", RCSCRIPTS_INITDDIR);
			exit(1);
		}

		if (-1 == execv(SHELL_PARSER, argv)) {
			DBG_MSG("Failed to execv %s!\n", SHELL_PARSER);
			exit(1);
		}
	} else {
		/***
		 ***   In parent
		 ***/

		struct sigaction act_new;
		struct sigaction act_old;
		struct pollfd poll_fds[2];
		char buf[PARSE_BUFFER_SIZE+1];
		char *stage1_data = NULL;
		size_t stage1_write_count = 0;
		size_t stage1_written = 0;
		int status = 0;

		DBG_MSG("Child pid = %i\n", child_pid);

		/* Set signal handler for SIGPIPE to empty in case bash errors
		 * out.  It will then close the write pipe, and instead of us
		 * getting SIGPIPE, we can handle the write error like normal.
		 */
		memset(&act_new, 0x00, sizeof(act_new));
		act_new.sa_handler = (void (*) (int))sig_handler;
		sigemptyset (&act_new.sa_mask);
		act_new.sa_flags = 0;
		sigaction(SIGPIPE, &act_new, &act_old);

		/* Close the sides of the pipes we do not use */
		close(CHILD_WRITE_PIPE(pipe_fds));
		CHILD_WRITE_PIPE(pipe_fds) = 0;
		close(CHILD_READ_PIPE(pipe_fds));
		CHILD_READ_PIPE(pipe_fds) = 0;

		stage1_data = malloc(OUTPUT_BUFFER_SIZE + 1);
		if (NULL == stage1_data) {
			DBG_MSG("Failed to allocate buffer!\n");
			goto error;
		}

		/* Pipe parse_rcscripts() to bash */
		stage1_write_count = generate_stage1(&stage1_data);
		if (-1 == stage1_write_count) {
			DBG_MSG("Failed to generate stage1!\n");
			goto error;
		}

#if 0
		int tmp_fd = open("bar", O_CREAT | O_TRUNC | O_RDWR, 0600);
		write(tmp_fd, stage1_data, stage1_write_count);
		close(tmp_fd);
#endif

		do {
			int tmp_count = 0;
			int do_write = 0;
			int do_read = 0;

			/* Check if we can write or read */
			poll_fds[WRITE_PIPE].fd = PARENT_WRITE_PIPE(pipe_fds);
			poll_fds[WRITE_PIPE].events = POLLOUT;
			poll_fds[READ_PIPE].fd = PARENT_READ_PIPE(pipe_fds);
			poll_fds[READ_PIPE].events = POLLIN | POLLPRI;
			if (stage1_written < stage1_write_count) {
				poll(poll_fds, 2, -1);
				if (poll_fds[WRITE_PIPE].revents & POLLOUT)
					do_write = 1;
			} else {
				poll(&(poll_fds[READ_PIPE]), 1, -1);
			}
			if ((poll_fds[READ_PIPE].revents & POLLIN)
			    || (poll_fds[READ_PIPE].revents & POLLPRI))
				do_read = 1;

			do {
				/* If we can write, or there is nothing to
				 * read, keep feeding the write pipe */
				if ((stage1_written >= stage1_write_count)
				    || (1 == do_read)
				    || (1 != do_write))
					break;

				tmp_count = write(PARENT_WRITE_PIPE(pipe_fds),
				                  &stage1_data[stage1_written],
				                  strlen(&stage1_data[stage1_written]));
				if ((-1 == tmp_count) && (EINTR != errno)) {
					DBG_MSG("Error writing to PARENT_WRITE_PIPE!\n");
					goto failed;
				}
				/* We were interrupted, try to write again */
				if (-1 == tmp_count) {
					errno = 0;
					/* Make sure we retry */
					tmp_count = 1;
					continue;
				}
				/* What was written before, plus what
				 * we wrote now as well as the ending
				 * '\0' of the line */
				stage1_written += tmp_count + 1;
			
				/* Close the write pipe if we done
				 * writing to get a EOF signaled to
				 * bash */
				if (stage1_written >= stage1_write_count) {
					close(PARENT_WRITE_PIPE(pipe_fds));
					PARENT_WRITE_PIPE(pipe_fds) = 0;
				}
			} while ((tmp_count > 0) && (stage1_written < stage1_write_count));
		
			/* Reset tmp_count for below read loop */
			tmp_count = 0;
			
			do {
				char *tmp_p;

				if (1 != do_read)
					continue;
				
				tmp_count = read(PARENT_READ_PIPE(pipe_fds), buf,
				                 PARSE_BUFFER_SIZE);
				if ((-1 == tmp_count) && (EINTR != errno)) {
					DBG_MSG("Error reading PARENT_READ_PIPE!\n");
					goto failed;
				}
				/* We were interrupted, try to read again */
				if ((-1 == tmp_count) || (0 == tmp_count)) {
					errno = 0;
					continue;
				}

				tmp_p = realloc(*data, write_count + tmp_count);
				if (NULL == tmp_p) {
					DBG_MSG("Failed to allocate buffer!\n");
					goto failed;
				}
				
				memcpy(&tmp_p[write_count], buf, tmp_count);

				*data = tmp_p;
				write_count += tmp_count;
			} while (tmp_count > 0);
		} while (!(poll_fds[READ_PIPE].revents & POLLHUP));

failed:
		/* Set old_errno to disable child exit code checking below */
		if (0 != errno)
			old_errno = errno;

		free(stage1_data);

		if (0 != PARENT_WRITE_PIPE(pipe_fds))
			close(PARENT_WRITE_PIPE(pipe_fds));
		close(PARENT_READ_PIPE(pipe_fds));

		/* Restore the old signal handler for SIGPIPE */
		sigaction(SIGPIPE, &act_old, NULL);

		/* Wait for bash to finish */
		waitpid(child_pid, &status, 0);
		/* If old_errno is set, we had an error in the read loop, so do
		 * not worry about the child's exit code */
		if (0 == old_errno) {
			if ((!WIFEXITED(status)) || (0 != WEXITSTATUS(status))) {
				DBG_MSG("Bash failed with status 0x%x!\n", status);
				return -1;
			}
		} else {
			/* Right, we had an error, so set errno, and exit */
			errno = old_errno;
			return -1;
		}
	}

	return write_count;

	/* Close parent side pipes */
error:
	/* Close all pipes */
	old_errno = errno;
	if (0 != CHILD_READ_PIPE(pipe_fds))
		close(CHILD_READ_PIPE(pipe_fds));
	if (0 != CHILD_WRITE_PIPE(pipe_fds))
		close(CHILD_WRITE_PIPE(pipe_fds));
	if (0 != PARENT_READ_PIPE(pipe_fds))
		close(PARENT_READ_PIPE(pipe_fds));
	if (0 != PARENT_WRITE_PIPE(pipe_fds))
		close(PARENT_WRITE_PIPE(pipe_fds));
	/* close() might have changed it */
	errno = old_errno;	
	
	return -1;
}

int write_legacy_stage3(FILE *output)
{
	service_info_t *info;
	char *service;
	int count;
	int index = 0;
	int dep_count;
	int i;

	if (-1 == fileno(output)) {
		DBG_MSG("Bad output stream!\n");
		return -1;
	}

	fprintf(output, "rc_type_ineed=2\n");
	fprintf(output, "rc_type_needsme=3\n");
	fprintf(output, "rc_type_iuse=4\n");
	fprintf(output, "rc_type_usesme=5\n");
	fprintf(output, "rc_type_ibefore=6\n");
	fprintf(output, "rc_type_iafter=7\n");
	fprintf(output, "rc_type_broken=8\n");
	fprintf(output, "rc_type_mtime=9\n");
	fprintf(output, "rc_index_scale=10\n\n");
	fprintf(output, "declare -a RC_DEPEND_TREE\n\n");

	list_for_each_entry(info, &service_info_list, node) {
		index++;
	}
	if (0 == index) {
		EERROR("No services to generate dependency tree for!\n");
		return -1;
	}

	fprintf(output, "RC_DEPEND_TREE[0]=%i\n\n", index);

	index = 1;

	list_for_each_entry(info, &service_info_list, node) {
		fprintf(output, "RC_DEPEND_TREE[%i]=\"%s\"\n",
		        index * 10, info->name);
		
		for (i = 0;i <= BROKEN;i++) {
			dep_count = 0;
			
			fprintf(output, "RC_DEPEND_TREE[%i+%i]=",
			        (index * 10), (i + 2));
			
			STRING_LIST_FOR_EACH(info->depend_info[i], service, count) {
				if (0 == dep_count)
					fprintf(output, "\"%s", service);
				else
					fprintf(output, " %s", service);

				dep_count++;
			}
			
			if (dep_count > 0)
				fprintf(output, "\"\n");
			else
				fprintf(output, "\n");
		}
		
		fprintf(output, "RC_DEPEND_TREE[%i+9]=\"%li\"\n\n",
		        index * 10, info->mtime);
		index++;
	}

	fprintf(output, "RC_GOT_DEPTREE_INFO=\"yes\"\n");
	
	info = service_get_virtual("logger");
	if (NULL == info) {
		DBG_MSG("No service provides the 'logger' logger virtual!\n");
		fprintf(output, "\nLOGGER_SERVICE=\n");
	} else {
		fprintf(output, "\nLOGGER_SERVICE=\"%s\"\n", info->name);
	}

	
	return 0;
}

int parse_cache(const char *data, size_t lenght)
{
	service_info_t *info;
	service_type_t type = ALL_SERVICE_TYPE_T;
	rcscript_info_t *rs_info;
	char *tmp_buf = NULL;
	char *rc_name = NULL;
	char *tmp_p;
	char *token;
	char *field;
	int count;
	int current = 0;
	int retval;

	if ((NULL == data) || (lenght <= 0)) {
		DBG_MSG("Invalid argument passed!\n");
		errno = EINVAL;
		goto error;
	}

	while (current < lenght) {
		count = buf_get_line((char *)data, lenght, current);

		tmp_buf = strndup(&(data[current]), count);
		if (NULL == tmp_buf) {
			DBG_MSG("Failed to allocate temporary buffer!\n");
			goto error;
		}
		tmp_p = tmp_buf;

		/* Strip leading spaces/tabs */
		while ((tmp_p[0] == ' ') || (tmp_p[0] == '\t'))
			tmp_p++;

		/* Get FIELD name and FIELD value */
		token = strsep(&tmp_p, " ");

		/* FIELD name empty/bogus? */
		if ((NULL == token)
		    || (0 == strlen(token))
		    /* We got an empty FIELD value */
		    || (NULL == tmp_p)
		    || (0 == strlen(tmp_p))) {
			DBG_MSG("Parsing stopped due to short read!\n");
			errno = EMSGSIZE;
			goto error;
		}

		if (0 == strcmp(token, FIELD_RCSCRIPT)) {
			DBG_MSG("Field = '%s', value = '%s'\n", token, tmp_p);
		
			/* Add the service to the list, and initialize all data */
			retval = service_add(tmp_p);
			if (-1 == retval) {
				DBG_MSG("Failed to add %s to service list!\n", tmp_p);
				goto error;
			}

			info = service_get_info(tmp_p);
			if (NULL == info) {
				DBG_MSG("Failed to get info for '%s'!\n", tmp_p);
				goto error;
			}
			/* Save the rc-script name for next passes of loop */
			rc_name = info->name;
			
			goto _continue;
		}

		if (NULL == rc_name) {
			DBG_MSG("Other fields should come after '%s'!\n", FIELD_RCSCRIPT);
			goto error;
		}

		if (0 == strcmp(token, FIELD_NEED))
			type = NEED;
		else if (0 == strcmp(token, FIELD_USE))
			type = USE;
		else if (0 == strcmp(token, FIELD_BEFORE))
			type = BEFORE;
		else if (0 == strcmp(token, FIELD_AFTER))
			type = AFTER;
		else if (0 == strcmp(token, FIELD_PROVIDE))
			type = PROVIDE;
		else if (0 == strcmp(token, FIELD_FAILED)) {
			type = BROKEN;

			/* FIXME: Need to think about what to do syntax BROKEN
			 * services */
			EWARN("'%s' has syntax errors, please correct!\n", rc_name);
		}

		if (type < ALL_SERVICE_TYPE_T) {
			/* Get the first value *
			 * As the values are passed to a bash function, and we
			 * then use 'echo $*' to parse them, they should only
			 * have one space between each value ... */
			token = strsep(&tmp_p, " ");

			/* Get the correct type name */
			field = service_type_names[type];
			
			while (NULL != token) {
				DBG_MSG("Field = '%s', service = '%s', value = '%s'\n",
				        field, rc_name, token);
				
				retval = service_add_dependency(rc_name, token, type);
				if (-1 == retval) {
					DBG_MSG("Failed to add dependency '%s' to service '%s', type '%s'!\n",
					        token, rc_name, field);
					goto error;
				}
				
				/* Get the next value (if any) */
				token = strsep(&tmp_p, " ");
			}
			
			goto _continue;
		}

		/* Fall through */
		DBG_MSG("Unknown FIELD in data!\n");

_continue:
		type = ALL_SERVICE_TYPE_T;
		current += count + 1;
		free(tmp_buf);
		/* Do not free 'rc_name', as it should be consistant
		 * across loops */
	}

	/* Set the mtimes
	 * FIXME: Can drop this when we no longer need write_legacy_stage3() */
	list_for_each_entry(rs_info, &rcscript_list, node) {
		rc_name = gbasename(rs_info->filename);
		if (NULL == service_get_info(rc_name))
			continue;
		
		retval = service_set_mtime(rc_name, rs_info->mtime);
		if (-1 == retval) {
			DBG_MSG("Failed to set mtime for service '%s'!\n", rc_name);
			return -1;
		}
	}

	return 0;

error:
	free(tmp_buf);
	
	return -1;
}

size_t parse_print_start(char **data, size_t index)
{
	size_t write_count = index;
	
	PRINT_TO_BUFFER(data, write_count, error,
		". /sbin/functions.sh\n"
		"[ -e /etc/rc.conf ] && . /etc/rc.conf\n"
		"\n"
	/*	"set -e\n" */
		"\n");

	return write_count;

error:
	return -1;
}

size_t parse_print_header(char *scriptname, char **data, size_t index)
{
	size_t write_count = index;
	
	PRINT_TO_BUFFER(data, write_count, error,
		"#*** %s ***\n"
		"\n"
		"myservice=\"%s\"\n"
		"echo \"RCSCRIPT ${myservice}\"\n"
		"\n",
		scriptname, scriptname);

	return write_count;

error:
	return -1;
}

size_t parse_print_body(char *scriptname, char **data, size_t index)
{
	size_t write_count = index;
	char *tmp_buf = NULL;
	char *tmp_ptr;
	char *base;
	char *ext;

	tmp_buf = strndup(scriptname, strlen(scriptname));
	if (NULL == tmp_buf) {
		DBG_MSG("Failed to allocate temporary buffer!\n");
		goto error;
	}

	/*
	 * Rather do the next block in C than bash, in case we want to
	 * use ash or another shell in the place of bash
	 */

	/* bash: base="${myservice%%.*}" */
	base = tmp_buf;
	tmp_ptr = strchr(tmp_buf, '.');
	if (NULL != tmp_ptr) {
		tmp_ptr[0] = '\0';
		tmp_ptr++;
	} else {
		tmp_ptr = tmp_buf;
	}
	/* bash: ext="${myservice##*.}" */
	ext = strrchr(tmp_ptr, '.');
	if (NULL == ext)
		ext = tmp_ptr;
	
	PRINT_TO_BUFFER(data, write_count, error,
		"\n"
		"(\n"
		"  # Get settings for rc-script ...\n"
		"  [ -e \"/etc/conf.d/${myservice}\" ] && \\\n"
		"  	. \"/etc/conf.d/${myservice}\"\n"
		"  [ -e /etc/conf.d/net ] && \\\n"
		"  [ \"%s\" = \"net\" ] && \\\n"
		"  [ \"%s\" != \"${myservice}\" ] && \\\n"
		"  	. /etc/conf.d/net\n"
		"  depend() {\n"
		"    return 0\n"
		"  }\n"
		"  \n"
		"  # Actual depend() function ...\n"
		"  (\n"
		"    set -e\n"
		"    . \"/etc/init.d/%s\" >/dev/null 2>&1\n"
		"    set +e\n"
		"    \n"
		"    need() {\n"
		"      [ \"$#\" -gt 0 ] && echo \"NEED $*\"; return 0\n"
		"    }\n"
		"    \n"
		"    use() {\n"
		"      [ \"$#\" -gt 0 ] && echo \"USE $*\"; return 0\n"
		"    }\n"
		"    \n"
		"    before() {\n"
		"      [ \"$#\" -gt 0 ] && echo \"BEFORE $*\"; return 0\n"
		"    }\n"
		"    \n"
		"    after() {\n"
		"      [ \"$#\" -gt 0 ] && echo \"AFTER $*\"; return 0\n"
		"    }\n"
		"    \n"
		"    provide() {\n"
		"      [ \"$#\" -gt 0 ] && echo \"PROVIDE $*\"; return 0\n"
		"    }\n"
		"    \n"
		"    depend\n"
		"  ) || echo \"FAILED ${myservice}\"\n"
		")\n"
		"\n\n",
		base, ext, scriptname);

	return write_count;

error:
	return -1;
}

