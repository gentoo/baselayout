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
#include <libgen.h>
#include <string.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>

#include "debug.h"
#include "depend.h"
#include "list.h"
#include "misc.h"
#include "parse.h"
#include "simple-regex.h"

#define READ_PIPE 0
#define WRITE_PIPE 1

#define PARSE_BUFFER_SIZE 80

LIST_HEAD(rcscript_list);

int parse_rcscript(char *scriptname, time_t mtime, FILE *output);
int generate_stage1(FILE *output);

void parse_print_start(FILE *output);
void parse_print_header(char *scriptname, time_t mtime, FILE *output);
void parse_print_body(FILE *output);
void parse_print_end(FILE *output);

int get_rcscripts(void) {
	rcscript_info_t *info;
	char **file_list = NULL;
	char *rcscript;
	char *rc_basename = NULL;
	char *rc_bname_ptr = NULL;
	char *confd_file = NULL;
	int count;

	file_list = ls_dir(INITD_DIR_NAME, 0);
	if (NULL == file_list) {
		DBG_MSG("'%s' is empty!\n", INITD_DIR_NAME);
		return -1;
	}

	STRING_LIST_FOR_EACH(file_list, rcscript, count) {
		rc_bname_ptr = strndup(rcscript, strlen(rcscript));
		if (NULL == rc_bname_ptr) {
			DBG_MSG("Failed to allocate buffer!\n");
			goto loop_error;
		}
		rc_basename = basename(rc_bname_ptr);
		
		    /* Is it a file? */
		if ((!is_file(rcscript, 1)) ||
		    /* Do not process scripts, source or backup files. */
		    (CHECK_FILE_EXTENSION(rcscript, ".c")) ||
		    (CHECK_FILE_EXTENSION(rcscript, ".bak")) ||
		    (CHECK_FILE_EXTENSION(rcscript, "~")))
		{
			DBG_MSG("'%s' is not a valid rc-script!\n",
					rc_basename);
		} else {
			DBG_MSG("Adding rc-script '%s' to list.\n",
					rc_basename);

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
			confd_file = strcatpaths(CONFD_DIR_NAME, rc_basename);
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
			free(rc_bname_ptr);

			list_add_tail(&info->node, &rcscript_list);

			continue;
			
loop_error:
			if (NULL != info)
				free(info->filename);
			free(info);
			free(rc_bname_ptr);
			
			goto error;
		}

		free(rc_bname_ptr);
	}

	/* Final check if we have some entries */
	if (NULL == file_list[0]) {
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
int check_rcscripts_mtime(char *cachefile) {
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
		if ((info->mtime > cache_mtime) ||
		    (info->confd_mtime > cache_mtime)) {
			DBG_MSG("'%s' have a later modification time than '%s'.\n",
					info->filename, cachefile);
			return -1;
		}
	}
	
	return 0;
}

/* Return 0 on success, -1 on error.  If it was critical, errno will be set. */
int parse_rcscript(char *scriptname, time_t mtime, FILE *output) {
	regex_data_t tmp_data;
	char *buf = NULL;
	char *tmp_buf = NULL;
	char *rc_basename = NULL;
	char *rc_bname_ptr = NULL;
	size_t lenght;
	int count;
	int current = 0;
	int got_depend = 0;
	int brace_count = 0;
	int depend_started = 0;

	if ((NULL == scriptname) || (0 == strlen(scriptname))) {
		DBG_MSG("Invalid argument passed!\n");
		errno = EINVAL;
		return -1;
	}
	
	if (-1 == fileno(output)) {
		DBG_MSG("Bad output stream!\n");
		return -1;
	}

	rc_bname_ptr = strndup(scriptname, strlen(scriptname));
	if (NULL == rc_bname_ptr) {
		DBG_MSG("Failed to allocate buffer!\n");
		return -1;
	}
	rc_basename = basename(rc_bname_ptr);
	
	if (-1 == file_map(scriptname, &buf, &lenght)) {
		DBG_MSG("Could not open '%s' for reading!\n",
				rc_basename);
		return -1;
	}
	
	while (current < lenght) {
		count = buf_get_line(buf, lenght, current);

		tmp_buf = strndup(&buf[current], count);
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
						rc_basename);
				errno = 0;
				goto error;
			}

			/* We do not want rc-scripts ending in '.sh' */
			if (CHECK_FILE_EXTENSION(scriptname, ".sh")) {
				EWARN("'%s' is invalid (should not end with '.sh')!\n",
						rc_basename);
				errno = 0;
				goto error;
			}
			DBG_MSG("Parsing '%s'.\n", basename(scriptname));

			parse_print_header(rc_basename, mtime, output);

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

			got_depend = 1;
			parse_print_body(output);
		}

		/* We have the depend function... */
		if (1 == got_depend) {
			/* Basic theory is that brace_count will be 0 when we
			 * have matching '{' and '}'
			 * FIXME:  This can fail for some cases */
			COUNT_CHAR_UP(tmp_buf, '{', brace_count);
			COUNT_CHAR_DN(tmp_buf, '}', brace_count);

			/* This is just to verify that we have started with
			 * the body of 'depend()' */
			COUNT_CHAR_UP(tmp_buf, '{', depend_started);

			/* Make sure depend() contain something, else bash
			 * errors out (empty function). */
			if ((depend_started > 0) && (0 == brace_count))
				fprintf(output, "  \treturn 0\n");

			/* Print the depend() function */
			fprintf(output, "  %s\n", tmp_buf);

			/* If COUNT=0, and SBCOUNT>0, it means we have read
			 * all matching '{' and '}' for depend(), so stop. */
			if ((depend_started > 0) && (0 == brace_count)) {
				parse_print_end(output);

				/* Make sure this is the last loop */
				current += lenght;
				goto _continue;
			}
		}
	
_continue:
		current += count + 1;
		free(tmp_buf);
	}

	free(rc_bname_ptr);
	file_unmap(buf, lenght);
	
	return 0;

error:
	free(tmp_buf);
	free(rc_bname_ptr);
	if (NULL != buf) {
		int old_errno = errno;
		file_unmap(buf, lenght);
		/* file_unmap() might have changed it */
		errno = old_errno;
	}

	return -1;
}


int generate_stage1(FILE *output) {
	rcscript_info_t *info;

	if (-1 == fileno(output)) {
		DBG_MSG("Bad output stream!\n");
		return -1;
	}

	parse_print_start(output);

	list_for_each_entry(info, &rcscript_list, node) {
		if (-1 == parse_rcscript(info->filename, info->mtime, output)) {
			DBG_MSG("Failed to parse rc-script!\n");

			/* If 'errno' is set, it is critical (hopefully) */
			if (0 != errno) {
				EERROR("Failed to parse rc-script!\n");
				/* Rather should just print error than abort
				 * for now, as it might be critical to get the
				 * box booted */
#if 0
				return -1;
#endif
			}
		}
	}
		
	return 0;
}

/* Returns data's lenght on success, else -1 on error. */
size_t generate_stage2(char **data) {
	/* parent_pfds is used to send data to the parent
	 * (thus the parent only use the read pipe, and the
	 *  child uses the write pipe)
	 */
	int parent_pfds[2];
	/* child_pfds is used to send data to the child
	 * (thus the child only use the read pipe, and the
	 *  parent uses the write pipe)
	 */
	int child_pfds[2];
	pid_t child_pid;
	size_t write_count = 0;
	int old_errno = 0;

	/* Pipe to send data to parent */
	if (-1 == pipe(parent_pfds)) {
		DBG_MSG("Failed to open 'parent_pfds' pipe!\n");
		goto error;
	}
	/* Pipe to send data to childd */
	if (-1 == pipe(child_pfds)) {
		DBG_MSG("Failed to open 'child_pfds' pipe!\n");
		/* Close parent_pfds */
		goto error_c_parent;
	}

	/* Zero data */
	*data = NULL;

	child_pid = fork();
	if (-1 == child_pid) {
		DBG_MSG("Failed to fork()!\n");
		/* Close all pipes */
		goto error_c_all;
	}
	if (0 == child_pid) {
		/***
		 ***   In child
		 ***/

		char *const argv[] = {
			"bash",
			"--noprofile",
			"--norc",
			NULL
		};

		/* Close the sides of the pipes we do not use */
		close(child_pfds[WRITE_PIPE]); /* Only used for reading */
		close(parent_pfds[READ_PIPE]); /* Only used for writing */

		/* dup2 child side read pipe to STDIN */
		dup2(child_pfds[READ_PIPE], STDIN_FILENO);
		/* dup2 child side write pipe to STDOUT */
		dup2(parent_pfds[WRITE_PIPE], STDOUT_FILENO);

		/* We need to be in INITD_DIR_NAME for 'before'/'after' '*' to work */
		if (-1 == chdir(INITD_DIR_NAME)) {
			DBG_MSG("Failed to chdir to '%s'!\n", INITD_DIR_NAME);
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

		FILE *write_pipe;
		int status;
		int read_count;
		char buf[PARSE_BUFFER_SIZE+1];

		DBG_MSG("Child pid = %i\n", child_pid);

		/* Close the sides of the pipes we do not use */
		close(parent_pfds[WRITE_PIPE]); /* Only used for reading */
		close(child_pfds[READ_PIPE]); /* Only used for writing */

		write_pipe = fdopen(child_pfds[WRITE_PIPE], "w");
		if (NULL == write_pipe) {
			DBG_MSG("Failed to open child_pfds for writing!\n");
			goto error_c_p_side;
		}

		/* Pipe parse_rcscripts() to bash */
		if (-1 == generate_stage1(write_pipe)) {
			DBG_MSG("Failed to generate stage1!\n");
			goto error_c_p_side;
		}

		fclose(write_pipe);

		do {
			read_count = read(parent_pfds[READ_PIPE], buf, PARSE_BUFFER_SIZE);
			if (-1 == read_count) {
				DBG_MSG("Error reading parent_pfds[READ_PIPE]!\n");
				/* Set old_errno to disable child exit code
				 * checking below */
				old_errno = errno;
				goto failed;
			}
			if (read_count > 0) {
				char *tmp_p;

				tmp_p = realloc(*data, write_count + read_count);
				if (NULL == tmp_p) {
					DBG_MSG("Failed to allocate buffer!\n");
					/* Set old_errno to disable child exit
					 * code checking below */
					old_errno = errno;
					goto failed;
				}
				
				memcpy(&tmp_p[write_count], buf, read_count);

				*data = tmp_p;				
				write_count += read_count;
			}
		} while (read_count > 0);

failed:
		close(parent_pfds[READ_PIPE]);

		/* Wait for bash to finish */
		waitpid(child_pid, &status, 0);
		/* If old_errno is set, we had an error in the read loop, so do
		 * not worry about the child's exit code */
		if (0 == old_errno) {
			if (!WIFEXITED(status) || (WEXITSTATUS(status) != 0)) {
				DBG_MSG("Bash failed with status 0x%x!\n", status);
				goto error;
			}
		} else {
			/* Right, we had an error, so set errno, and exit */
			errno = old_errno;
			goto error;
		}
	}

	return write_count;

	/* Close parent side pipes */
error_c_p_side:
	old_errno = errno;
	close(child_pfds[WRITE_PIPE]);
	close(parent_pfds[READ_PIPE]);
	/* close() might have changed it */
	errno = old_errno;	
	goto error;
	
	/* Close all pipes */
error_c_all:
	old_errno = errno;
	close(child_pfds[READ_PIPE]);
	close(child_pfds[WRITE_PIPE]);
	/* close() might have changed it */
	errno = old_errno;	
	
	/* Only close parent's pipes */
error_c_parent:
	old_errno = errno;
	close(parent_pfds[READ_PIPE]);
	close(parent_pfds[WRITE_PIPE]);
	/* close() might have changed it */
	errno = old_errno;	
	
error:
	return -1;
}

int write_legacy_stage3(FILE *output) {
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
	fprintf(output, "rc_type_parallel=9\n");
	fprintf(output, "rc_type_mtime=10\n");
	fprintf(output, "rc_index_scale=11\n\n");
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
		fprintf(output, "RC_DEPEND_TREE[%i]=\"%s\"\n", index*11, info->name);
		
		for (i = 0;i <= BROKEN;i++) {
			dep_count = 0;
			
			fprintf(output, "RC_DEPEND_TREE[%i+%i]=", (index * 11), (i + 2));
			
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
		
		fprintf(output, "RC_DEPEND_TREE[%i+9]=", index*11);
		switch (info->parallel) {
			case 0:
				fprintf(output, "\"no\"");
				break;
			case 1:
				fprintf(output, "\"yes\"");
				break;
		}
		fprintf(output, "\n");

		fprintf(output, "RC_DEPEND_TREE[%i+10]=%li\n\n", index*11, info->mtime);
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

int parse_cache(const char *data, size_t lenght) {
	service_info_t *info;
	service_type_t type = ALL_SERVICE_TYPE_T;
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

		tmp_buf = strndup(&data[current], count);
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
		if ((NULL == token) || (0 == strlen(token)) ||
		    /* We got an empty FIELD value */
		    (NULL == tmp_p) || (0 == strlen(tmp_p))) {
			DBG_MSG("Parsing stopped due to short read!\n");
			errno = EMSGSIZE;
			goto error;
		}

		if (0 == strcmp(token, FIELD_RCSCRIPT)) {
			DBG_MSG("Field = '%s', value = '%s'\n", token, tmp_p);
		
			/* Add the service to the list, and initialize all data */
			retval = service_add(tmp_p);
			if (-1 == retval) {
				DBG_MSG("Failed to add %s to service list!\n",
						tmp_p);
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

		if (0 == strcmp(token, FIELD_NEED)) {
			type = NEED;
			goto have_dep_field;
		}

		if (0 == strcmp(token, FIELD_USE)) {
			type = USE;
			goto have_dep_field;
		}

		if (0 == strcmp(token, FIELD_BEFORE)) {
			type = BEFORE;
			goto have_dep_field;
		}

		if (0 == strcmp(token, FIELD_AFTER)) {
			type = AFTER;
			goto have_dep_field;
		}

		if (0 == strcmp(token, FIELD_PROVIDE)) {
			type = PROVIDE;
			goto have_dep_field;
		}

		if (type < ALL_SERVICE_TYPE_T) {
have_dep_field:
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

		if (0 == strcmp(token, FIELD_PARALLEL)) {
			/* Just use the first value, and ignore the rest */
			token = strsep(&tmp_p, " ");

			retval = service_set_parallel(rc_name, token);
			if (-1 == retval) {
				DBG_MSG("Failed to set parallel for service '%s'!\n",
						rc_name);
				/* We do not care if this fails */
#if 0
				goto error;
#endif
			}

			/* Some debugging in case we have some corruption or
			 * other issues */
			token = strsep(&tmp_p, " ");
			if (NULL != token)
				DBG_MSG("Too many falues for field '%s'!\n",
						FIELD_MTIME);
			
			goto _continue;
		}

		if (0 == strcmp(token, FIELD_MTIME)) {
			time_t mtime = 0;
			
			/* Just use the first value, and ignore the rest */
			token = strsep(&tmp_p, " ");

			if (NULL != token)
				mtime = atoi(token);
			
			retval = service_set_mtime(rc_name, mtime);
			if (-1 == retval) {
				DBG_MSG("Failed to set mtime for service '%s'!\n",
						rc_name);
				goto error;
			}

			/* Some debugging in case we have some corruption or
			 * other issues */
			token = strsep(&tmp_p, " ");
			if (NULL != token)
				DBG_MSG("Too many falues for field '%s'!\n",
						FIELD_MTIME);
			
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

	return 0;

error:
	free(tmp_buf);
	
	return -1;
}

void parse_print_start(FILE *output) {
	fprintf(output, "source /sbin/functions.sh\n\n");
	fprintf(output, "need() {\n");
	fprintf(output, " [ -n \"$*\" ] && echo \"NEED $*\"; return 0\n");
	fprintf(output, "}\n\n");
	fprintf(output, "use() {\n");
	fprintf(output, " [ -n \"$*\" ] && echo \"USE $*\"; return 0\n");
	fprintf(output, "}\n\n");
	fprintf(output, "before() {\n");
	fprintf(output, " [ -n \"$*\" ] && echo \"BEFORE $*\"; return 0\n");
	fprintf(output, "}\n\n");
	fprintf(output, "after() {\n");
	fprintf(output, " [ -n \"$*\" ] && echo \"AFTER $*\"; return 0\n");
	fprintf(output, "}\n\n");
	fprintf(output, "provide() {\n");
	fprintf(output, " [ -n \"$*\" ] && echo \"PROVIDE $*\"; return 0\n");
	fprintf(output, "}\n\n");
	fprintf(output, "parallel() {\n");
	fprintf(output, " [ -n \"$*\" ] && echo \"PARALLEL $*\"; return 0\n");
	fprintf(output, "}\n\n");
}

void parse_print_header(char *scriptname, time_t mtime, FILE *output) {
	fprintf(output, "#*** %s ***\n\n", scriptname);
	fprintf(output, "myservice=\"%s\"\n", scriptname);
	fprintf(output, "echo \"RCSCRIPT ${myservice}\"\n\n");
	fprintf(output, "echo \"MTIME %li\"\n\n", mtime);
}

void parse_print_body(FILE *output) {
	fprintf(output, "(\n");
	fprintf(output, "  # Get settings for rc-script ...\n");
	fprintf(output, "  [ -e \"/etc/conf.d/${myservice}\" ] && \\\n");
	fprintf(output, "  	source \"/etc/conf.d/${myservice}\"\n");
	fprintf(output, "  [ -e /etc/conf.d/net ] && \\\n");
	fprintf(output, "  [ \"${myservice%%.*}\" = \"net\" ] && \\\n");
	fprintf(output, "  [ \"${myservice##*.}\" != \"${myservice}\" ] && \\\n");
	fprintf(output, "  	source /etc/conf.d/net\n");
	fprintf(output, "  [ -e /etc/rc.conf ] && source /etc/rc.conf\n\n");
	fprintf(output, "  depend() {\n");
	fprintf(output, "    return 0\n");
	fprintf(output, "  }\n\n");
	fprintf(output, "  # Actual depend() function ...\n");
}

void parse_print_end(FILE *output) {
	fprintf(output, "\n");
	fprintf(output, "  depend\n");
	fprintf(output, ")\n\n");
}

