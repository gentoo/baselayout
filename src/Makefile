CC = gcc
LD = gcc

TARGETS = filefuncs.so

all: $(TARGETS)

filefuncs.o: filefuncs.c
	$(CC) -shared -Wall -DHAVE_CONFIG_H -c -O -fPIC -I/usr/include/awk $^

filefuncs.so: filefuncs.o
	$(LD) -o $@ -shared $^

clean:
	rm -f $(TARGETS)
	rm -f *.o *~ core

