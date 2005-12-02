#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <librcscripts/dynbuf.h>

int main()
{
  dynamic_buffer_t *dynbuf;
  char buf[255];

  dynbuf = new_dyn_buf ();
  
  sprintf_dyn_buf (dynbuf, "Hello");
  write_dyn_buf (dynbuf, " ", 1);
  sprintf_dyn_buf (dynbuf, "world!\n");
  read_dyn_buf (dynbuf, buf, 255);
  
  free_dyn_buf (dynbuf);

  if (0 != strncmp (buf, "Hello world!\n", strlen ("Hello world!\n")))
    return 1;

  return 0;
}
