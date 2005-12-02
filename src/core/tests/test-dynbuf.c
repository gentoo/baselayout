#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <librcscripts/dynbuf.h>

#define TEST_STRING1	 "Hello"
#define TEST_STRING2	 " "
#define TEST_STRING3	 "world"
#define TEST_STRING4	 "!\n"
#define TEST_STRING_FULL TEST_STRING1 TEST_STRING2 TEST_STRING3 TEST_STRING4

int main()
{
  dynamic_buffer_t *dynbuf;
  char buf[255];
  int length, total = 0;

  dynbuf = new_dyn_buf ();
  if (NULL == dynbuf)
    {
      fprintf (stderr, "Failed to allocate dynamic buffer.\n");
      return 1;
    }
  
  length = sprintf_dyn_buf (dynbuf, TEST_STRING1);
  if (length != strlen (TEST_STRING1))
    {
      fprintf (stderr, "sprintf_dyn_buf() returned wrong length (pass 1)!\n");
      free_dyn_buf (dynbuf);
      return 1;
    }
  total += length;
  
  length = write_dyn_buf (dynbuf, TEST_STRING2, strlen (TEST_STRING2));
  if (length != strlen (TEST_STRING2))
    {
      fprintf (stderr, "write_dyn_buf() returned wrong length (pass 1)!\n");
      free_dyn_buf (dynbuf);
      return 1;
    }
  total += length;

  length = sprintf_dyn_buf (dynbuf, TEST_STRING3);
  if (length != strlen (TEST_STRING3))
    {
      fprintf (stderr, "sprintf_dyn_buf() returned wrong length (pass 2)!\n");
      free_dyn_buf (dynbuf);
      return 1;
    }
  total += length;
  
  length = write_dyn_buf (dynbuf, TEST_STRING4, strlen (TEST_STRING4));
  if (length != strlen (TEST_STRING4))
    {
      fprintf (stderr, "write_dyn_buf() returned wrong length (pass 2)!\n");
      free_dyn_buf (dynbuf);
      return 1;
    }  
  total += length;
  
  length = read_dyn_buf (dynbuf, buf, total / 2);
  if (length != total / 2)
    {
      fprintf (stderr, "read_dyn_buf() returned wrong length (pass 1)!\n");
      free_dyn_buf (dynbuf);
      return 1;
    }  
  
  length = read_dyn_buf (dynbuf, (buf + (total / 2)), total);
  if (length != (total - (total / 2)))
    {
      fprintf (stderr, "read_dyn_buf() returned wrong length (pass 2)!\n");
      free_dyn_buf (dynbuf);
      return 1;
    }  
  
  free_dyn_buf (dynbuf);

  if (0 != strncmp (buf, TEST_STRING_FULL, strlen (TEST_STRING_FULL)))
    {
      fprintf (stderr, "Written and read strings differ!\n");
      return 1;
    }

  return 0;
}
