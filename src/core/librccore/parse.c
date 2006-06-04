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

#include "rcscripts/rccore.h"

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

static size_t parse_rcscript (char *scriptname, dyn_buf_t *data);

static size_t parse_print_start (dyn_buf_t *data);
static size_t parse_print_header (char *scriptname, dyn_buf_t *data);
static size_t parse_print_body (char *scriptname, dyn_buf_t *data);

/* Return count on success, -1 on error.  If it was critical, errno will be set. */
size_t
parse_rcscript (char *scriptname, dyn_buf_t *data)
{
  regex_data_t tmp_data;
  dyn_buf_t *dynbuf = NULL;
  char *buf = NULL;
  size_t write_count = 0;
  size_t tmp_count;

  if (!check_arg_dyn_buf (data))
    return -1;

  if (!check_arg_str (scriptname))
    return -1;

  dynbuf = new_dyn_buf_mmap_file (scriptname);
  if (NULL == dynbuf)
    {
      DBG_MSG ("Could not open '%s' for reading!\n", gbasename (scriptname));
      return -1;
    }

  DBG_MSG ("Parsing '%s'.\n", gbasename (scriptname));

  tmp_count = parse_print_header (gbasename (scriptname), data);
  if (-1 == tmp_count)
    {
      DBG_MSG ("Failed to call parse_print_header()!\n");
      goto error;
    }
  write_count += tmp_count;

  while (NULL != (buf = read_line_dyn_buf(dynbuf)))
    {
      /* Check for lines with comments, and skip them */
      DO_REGEX (tmp_data, buf, "^[ \t]*#", error);
      if (REGEX_MATCH (tmp_data))
	{
	  free (buf);
	  continue;
	}

      /* If the line contains 'depend()', call parse_print_body () and break */
      DO_REGEX (tmp_data, buf, "depend[ \t]*()[ \t]*{?", error);
      if (REGEX_MATCH (tmp_data))
	{
	  DBG_MSG ("Got 'depend()' function.\n");

	  tmp_count = parse_print_body (gbasename (scriptname), data);
	  if (-1 == tmp_count)
	    {
	      DBG_MSG ("Failed to call parse_print_body()!\n");
	      goto error;
	    }

	  write_count += tmp_count;

	  /* This is the last loop */
	  free (buf);
	  break;
	}

      free (buf);
    }

  /* read_line_dyn_buf() returned NULL with errno set */
  if ((NULL == buf) && (0 != errno))
    {
      DBG_MSG ("Failed to read line from dynamic buffer!\n");
      free_dyn_buf (dynbuf);

      return -1;
    }

  free_dyn_buf (dynbuf);

  return write_count;

error:
  if (NULL != buf)
    free (buf);
  if (NULL != dynbuf)
    free_dyn_buf (dynbuf);

  return -1;
}


size_t
generate_stage1 (dyn_buf_t *data)
{
  rcscript_info_t *info;
  size_t write_count = 0;
  size_t tmp_count;

  if (!check_arg_dyn_buf (data))
    return -1;

  write_count = parse_print_start (data);
  if (-1 == write_count)
    {
      DBG_MSG ("Failed to call parse_print_start()!\n");
      return -1;
    }

  list_for_each_entry (info, &rcscript_list, node)
    {
      tmp_count = parse_rcscript (info->filename, data);
      if (-1 == tmp_count)
	{
	  DBG_MSG ("Failed to parse '%s'!\n", gbasename (info->filename));

	  /* If 'errno' is set, it is critical (hopefully) */
	  if (0 != errno)
	    return -1;
	}
      else
	{
	  write_count += tmp_count;
	}
    }

  return write_count;
}

/* Empty signal handler for SIGPIPE */
static void
sig_handler (int signum)
{
  return;
}

/* Returns data's lenght on success, else -1 on error. */
size_t
generate_stage2 (dyn_buf_t *data)
{
  int pipe_fds[2][2] = { {0, 0}, {0, 0} };
  pid_t child_pid;
  size_t write_count = 0;
  int old_errno = 0;

  if (!check_arg_dyn_buf (data))
    return -1;

  /* Pipe to send data to parent */
  if (-1 == pipe (pipe_fds[0]))
    {
      DBG_MSG ("Failed to open pipe!\n");
      goto error;
    }
  /* Pipe to send data to child */
  if (-1 == pipe (pipe_fds[1]))
    {
      DBG_MSG ("Failed to open pipe!\n");
      /* Close parent_pfds */
      goto error;
    }

  child_pid = fork ();
  if (-1 == child_pid)
    {
      DBG_MSG ("Failed to fork()!\n");
      /* Close all pipes */
      goto error;
    }
  if (0 == child_pid)
    {
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
      close (PARENT_WRITE_PIPE (pipe_fds));
      close (PARENT_READ_PIPE (pipe_fds));

      /* dup2 child side read pipe to STDIN */
      dup2 (CHILD_READ_PIPE (pipe_fds), STDIN_FILENO);
      /* dup2 child side write pipe to STDOUT */
      dup2 (CHILD_WRITE_PIPE (pipe_fds), STDOUT_FILENO);

      /* We need to be in RCSCRIPTS_INITDDIR for 'before'/'after' '*' to work */
      if (-1 == chdir (RCSCRIPTS_INITDDIR))
	{
	  DBG_MSG ("Failed to chdir to '%s'!\n", RCSCRIPTS_INITDDIR);
	  exit (EXIT_FAILURE);
	}

      if (-1 == execv (SHELL_PARSER, argv))
	{
	  DBG_MSG ("Failed to execv %s!\n", SHELL_PARSER);
	  exit (EXIT_FAILURE);
	}
    }
  else
    {
      /***
       ***   In parent
       ***/

      dyn_buf_t *stage1_data;
      struct sigaction act_new;
      struct sigaction act_old;
      struct pollfd poll_fds[2];
      int status = 0;

      DBG_MSG ("Child pid = %i\n", child_pid);

      /* Set signal handler for SIGPIPE to empty in case bash errors
       * out.  It will then close the write pipe, and instead of us
       * getting SIGPIPE, we can handle the write error like normal.
       */
      memset (&act_new, 0x00, sizeof (act_new));
      act_new.sa_handler = (void (*)(int)) sig_handler;
      sigemptyset (&act_new.sa_mask);
      act_new.sa_flags = 0;
      sigaction (SIGPIPE, &act_new, &act_old);

      /* Close the sides of the pipes we do not use */
      close (CHILD_WRITE_PIPE (pipe_fds));
      CHILD_WRITE_PIPE (pipe_fds) = 0;
      close (CHILD_READ_PIPE (pipe_fds));
      CHILD_READ_PIPE (pipe_fds) = 0;

      stage1_data = new_dyn_buf ();
      if (NULL == stage1_data)
	{
	  DBG_MSG ("Failed to allocate dynamic buffer!\n");
	  goto error;
	}

      /* Pipe parse_rcscripts() to bash */
      if (-1 == generate_stage1 (stage1_data))
	{
	  DBG_MSG ("Failed to generate stage1!\n");
	  goto error;
	}

#if 0
      int tmp_fd = open ("bar", O_CREAT | O_TRUNC | O_RDWR, 0600);
      write (tmp_fd, stage1_data->data, stage1_data->wr_index);
      close (tmp_fd);
#endif

      do
	{
	  int tmp_count = 0;
	  int do_write = 0;
	  int do_read = 0;

	  /* Check if we can write or read */
	  poll_fds[WRITE_PIPE].fd = PARENT_WRITE_PIPE (pipe_fds);
	  poll_fds[WRITE_PIPE].events = POLLOUT;
	  poll_fds[READ_PIPE].fd = PARENT_READ_PIPE (pipe_fds);
	  poll_fds[READ_PIPE].events = POLLIN | POLLPRI;
	  if (!dyn_buf_rd_eof (stage1_data))
	    {
	      poll (poll_fds, 2, -1);
	      if (poll_fds[WRITE_PIPE].revents & POLLOUT)
		do_write = 1;
	    }
	  else
	    {
	      poll (&(poll_fds[READ_PIPE]), 1, -1);
	    }
	  if ((poll_fds[READ_PIPE].revents & POLLIN)
	      || (poll_fds[READ_PIPE].revents & POLLPRI))
	    do_read = 1;

	  do
	    {
	      /* While we can write, or there is nothing to
	       * read, keep feeding the write pipe */
	      if ((dyn_buf_rd_eof (stage1_data))
		  || (1 == do_read)
		  || (1 != do_write))
		break;

	      tmp_count = read_dyn_buf_to_fd (PARENT_WRITE_PIPE (pipe_fds),
					      stage1_data, PARSE_BUFFER_SIZE);
	      if ((-1 == tmp_count) && (EINTR != errno))
		{
		  DBG_MSG ("Error writing to PARENT_WRITE_PIPE!\n");
		  goto failed;
		}
	      /* We were interrupted, try to write again */
	      if (-1 == tmp_count)
		{
		  errno = 0;
		  /* Make sure we retry */
		  tmp_count = 1;
		  continue;
		}

	      /* Close the write pipe if we done
	       * writing to get a EOF signaled to
	       * bash */
	      if (dyn_buf_rd_eof (stage1_data))
		{
		  close (PARENT_WRITE_PIPE (pipe_fds));
		  PARENT_WRITE_PIPE (pipe_fds) = 0;
		}
	    }
	  while ((tmp_count > 0) && (!dyn_buf_rd_eof (stage1_data)));

	  /* Reset tmp_count for below read loop */
	  tmp_count = 0;

	  do
	    {
	      if (1 != do_read)
		continue;

	      tmp_count = write_dyn_buf_from_fd (PARENT_READ_PIPE (pipe_fds),
						 data, PARSE_BUFFER_SIZE);
	      if ((-1 == tmp_count) && (EINTR != errno))
		{
		  DBG_MSG ("Error reading PARENT_READ_PIPE!\n");
		  goto failed;
		}
	      /* We were interrupted, try to read again */
	      if ((-1 == tmp_count) || (0 == tmp_count))
		{
		  errno = 0;
		  continue;
		}

	      write_count += tmp_count;
	    }
	  while (tmp_count > 0);
	}
      while (!(poll_fds[READ_PIPE].revents & POLLHUP));

failed:
      /* Set old_errno to disable child exit code checking below */
      if (0 != errno)
	old_errno = errno;

      free_dyn_buf (stage1_data);

      if (0 != PARENT_WRITE_PIPE (pipe_fds))
	close (PARENT_WRITE_PIPE (pipe_fds));
      close (PARENT_READ_PIPE (pipe_fds));

      /* Restore the old signal handler for SIGPIPE */
      sigaction (SIGPIPE, &act_old, NULL);

      /* Wait for bash to finish */
      waitpid (child_pid, &status, 0);
      /* If old_errno is set, we had an error in the read loop, so do
       * not worry about the child's exit code */
      if (0 == old_errno)
	{
	  if ((!WIFEXITED (status)) || (0 != WEXITSTATUS (status)))
	    {
	      /* FIXME: better errno ? */
	      errno = ECANCELED;
	      DBG_MSG ("Bash failed with status 0x%x!\n", status);

	      return -1;
	    }
	}
      else
	{
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
  if (0 != CHILD_READ_PIPE (pipe_fds))
    close (CHILD_READ_PIPE (pipe_fds));
  if (0 != CHILD_WRITE_PIPE (pipe_fds))
    close (CHILD_WRITE_PIPE (pipe_fds));
  if (0 != PARENT_READ_PIPE (pipe_fds))
    close (PARENT_READ_PIPE (pipe_fds));
  if (0 != PARENT_WRITE_PIPE (pipe_fds))
    close (PARENT_WRITE_PIPE (pipe_fds));
  /* close() might have changed it */
  errno = old_errno;

  return -1;
}

int
write_legacy_stage3 (FILE * output)
{
  service_info_t *info;
  char *service;
  int count;
  int sindex = 0;
  int dep_count;
  int i;

  if (!check_arg_fp (output))
    return -1;

  fprintf (output, "rc_type_ineed=2\n");
  fprintf (output, "rc_type_needsme=3\n");
  fprintf (output, "rc_type_iuse=4\n");
  fprintf (output, "rc_type_usesme=5\n");
  fprintf (output, "rc_type_ibefore=6\n");
  fprintf (output, "rc_type_iafter=7\n");
  fprintf (output, "rc_type_broken=8\n");
  fprintf (output, "rc_type_mtime=9\n");
  fprintf (output, "rc_index_scale=10\n\n");
  fprintf (output, "declare -a RC_DEPEND_TREE\n\n");

  list_for_each_entry (info, &service_info_list, node)
    {
      sindex++;
    }
  if (0 == sindex)
    {
      EERROR ("No services to generate dependency tree for!\n");
      return -1;
    }

  fprintf (output, "RC_DEPEND_TREE[0]=%i\n\n", sindex);

  sindex = 1;

  list_for_each_entry (info, &service_info_list, node)
    {
      fprintf (output, "RC_DEPEND_TREE[%i]=\"%s\"\n", sindex * 10, info->name);

      for (i = 0; i <= BROKEN; i++)
	{
	  dep_count = 0;

	  fprintf (output, "RC_DEPEND_TREE[%i+%i]=", (sindex * 10), (i + 2));

	  str_list_for_each_item (info->depend_info[i], service, count)
	    {
	      if (0 == dep_count)
		fprintf (output, "\"%s", service);
	      else
		fprintf (output, " %s", service);

	      dep_count++;
	    }

	  if (dep_count > 0)
	    fprintf (output, "\"\n");
	  else
	    fprintf (output, "\n");
	}

      fprintf (output, "RC_DEPEND_TREE[%i+9]=\"%li\"\n\n",
	       sindex * 10, info->mtime);
      sindex++;
    }

  fprintf (output, "RC_GOT_DEPTREE_INFO=\"yes\"\n");

  info = service_get_virtual ("logger");
  if (NULL == info)
    {
      DBG_MSG ("No service provides the 'logger' logger virtual!\n");
      fprintf (output, "\nLOGGER_SERVICE=\n");
    }
  else
    {
      fprintf (output, "\nLOGGER_SERVICE=\"%s\"\n", info->name);
    }


  return 0;
}

int
parse_cache (const dyn_buf_t *data)
{
  service_info_t *info;
  service_type_t type = ALL_SERVICE_TYPE_T;
  rcscript_info_t *rs_info;
  char *buf = NULL;
  char *rc_name = NULL;
  char *str_ptr;
  char *token;
  char *field;
  int retval;

  if (!check_arg_dyn_buf ((dyn_buf_t *) data))
    goto error;

  while (NULL != (buf = read_line_dyn_buf ((dyn_buf_t *) data)))
    {
      str_ptr = buf;

      /* Strip leading spaces/tabs */
      while ((str_ptr[0] == ' ') || (str_ptr[0] == '\t'))
	str_ptr++;

      /* Get FIELD name and FIELD value */
      token = strsep (&str_ptr, " ");

      /* FIELD name empty/bogus? */
      if ((!check_str (token))
	  /* We got an empty FIELD value */
	  || (!check_str (str_ptr)))
	{
	  errno = EMSGSIZE;
	  DBG_MSG ("Parsing stopped due to short read!\n");

	  goto error;
	}

      if (0 == strcmp (token, FIELD_RCSCRIPT))
	{
	  DBG_MSG ("Field = '%s', value = '%s'\n", token, str_ptr);

	  /* Add the service to the list, and initialize all data */
	  retval = service_add (str_ptr);
	  if (-1 == retval)
	    {
	      DBG_MSG ("Failed to add %s to service list!\n", str_ptr);
	      goto error;
	    }

	  info = service_get_info (str_ptr);
	  if (NULL == info)
	    {
	      DBG_MSG ("Failed to get info for '%s'!\n", str_ptr);
	      goto error;
	    }
	  /* Save the rc-script name for next passes of loop */
	  rc_name = info->name;

	  goto _continue;
	}

      if (NULL == rc_name)
	{
	  DBG_MSG ("Other fields should come after '%s'!\n", FIELD_RCSCRIPT);
	  goto error;
	}

      if (0 == strcmp (token, FIELD_NEED))
	type = NEED;
      else if (0 == strcmp (token, FIELD_USE))
	type = USE;
      else if (0 == strcmp (token, FIELD_BEFORE))
	type = BEFORE;
      else if (0 == strcmp (token, FIELD_AFTER))
	type = AFTER;
      else if (0 == strcmp (token, FIELD_PROVIDE))
	type = PROVIDE;
      else if (0 == strcmp (token, FIELD_FAILED))
	{
	  type = BROKEN;

	  /* FIXME: Need to think about what to do syntax BROKEN
	   * services */
	  EWARN ("'%s' has syntax errors, please correct!\n", rc_name);
	}

      if (type < ALL_SERVICE_TYPE_T)
	{
	  /* Get the first value *
	   * As the values are passed to a bash function, and we
	   * then use 'echo $*' to parse them, they should only
	   * have one space between each value ... */
	  token = strsep (&str_ptr, " ");

	  /* Get the correct type name */
	  field = service_type_names[type];

	  while (NULL != token)
	    {
	      DBG_MSG ("Field = '%s', service = '%s', value = '%s'\n",
		       field, rc_name, token);

	      retval = service_add_dependency (rc_name, token, type);
	      if (-1 == retval)
		{
		  DBG_MSG
		   ("Failed to add dependency '%s' to service '%s', type '%s'!\n",
		    token, rc_name, field);
		  goto error;
		}

	      /* Get the next value (if any) */
	      token = strsep (&str_ptr, " ");
	    }

	  goto _continue;
	}

      /* Fall through */
      DBG_MSG ("Unknown FIELD in data!\n");

_continue:
      type = ALL_SERVICE_TYPE_T;
      free (buf);
      /* Do not free 'rc_name', as it should be consistant
       * across loops */
    }

  /* read_line_dyn_buf() returned NULL with errno set */
  if ((NULL == buf) && (0 != errno))
    {
      DBG_MSG ("Failed to read line from dynamic buffer!\n");
      return -1;
    }

  /* Set the mtimes
   * FIXME: Can drop this when we no longer need write_legacy_stage3() */
  list_for_each_entry (rs_info, &rcscript_list, node)
    {
      rc_name = gbasename (rs_info->filename);
      if (NULL == service_get_info (rc_name))
	continue;

      retval = service_set_mtime (rc_name, rs_info->mtime);
      if (-1 == retval)
	{
	  DBG_MSG ("Failed to set mtime for service '%s'!\n", rc_name);
	  return -1;
	}
    }

  return 0;

error:
  free (buf);

  return -1;
}

size_t
parse_print_start (dyn_buf_t *data)
{
  size_t write_count;

  if (!check_arg_dyn_buf (data))
    return -1;

  write_count =
   sprintf_dyn_buf (data,
		    ". /sbin/functions.sh\n"
		    "[ -e /etc/rc.conf ] && . /etc/rc.conf\n"
		    "\n"
		    /*      "set -e\n" */
		    "\n");

  return write_count;
}

size_t
parse_print_header (char *scriptname, dyn_buf_t *data)
{
  size_t write_count;

  if (!check_arg_dyn_buf (data))
    return -1;

  write_count =
   sprintf_dyn_buf (data,
		    "#*** %s ***\n"
		    "\n"
		    "myservice=\"%s\"\n"
		    "echo \"RCSCRIPT ${myservice}\"\n"
		    "\n", scriptname, scriptname);

  return write_count;
}

size_t
parse_print_body (char *scriptname, dyn_buf_t *data)
{
  size_t write_count;
  char *buf = NULL;
  char *str_ptr;
  char *base;
  char *ext;

  if (!check_arg_dyn_buf (data))
    return -1;

  buf = xstrndup (scriptname, strlen (scriptname));
  if (NULL == buf)
    return -1;

  /*
   * Rather do the next block in C than bash, in case we want to
   * use ash or another shell in the place of bash
   */

  /* bash: base="${myservice%%.*}" */
  base = buf;
  str_ptr = strchr (buf, '.');
  if (NULL != str_ptr)
    {
      str_ptr[0] = '\0';
      str_ptr++;
    }
  else
    {
      str_ptr = buf;
    }
  /* bash: ext="${myservice##*.}" */
  ext = strrchr (str_ptr, '.');
  if (NULL == ext)
    ext = str_ptr;

  write_count =
   sprintf_dyn_buf (data,
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
		    ")\n" "\n\n", base, ext, scriptname);

  return write_count;
}
