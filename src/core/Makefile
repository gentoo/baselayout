CC = gcc
CFLAGS = -Wall
EXTRA_CFLAGS = -DLEGACY_DEPSCAN
STRIP = strip

DEPSCAN = depscan

TARGETS = $(DEPSCAN)

all: $(TARGETS)

.ALL: all

OBJS = \
	parse.o \
	depend.o \
	simple-regex.o \
	misc.o

HEADERS = \
	parse.h \
	depend.h \
	simple-regex.h \
	misc.h \
	debug.h

ifeq ($(DEBUG),1)
  CFLAGS += -ggdb3
  EXTRA_CFLAGS += -DRC_DEBUG
endif

$(DEPSCAN): $(OBJS) $(DEPSCAN).o
	$(CC) $(CFLAGS) $(EXTRA_CFLAGS) -o $@ $^

$(OBJS): $(HEADERS)

.c.o:
	$(CC) $(CFLAGS) $(EXTRA_CFLAGS) -c -o $@ $<

strip: $(TARGETS)
	$(STRIP) -s --remove-section=.note --remove-section=.comment $(TARGETS)

clean:
	rm -f *.o $(TARGETS)
