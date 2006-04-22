# Copyright 1999-2004 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

CC = gcc
LD = gcc

CFLAGS ?= -Wall -O2
DESTDIR =

BIN_TARGETS =
SBIN_TARGETS = consoletype runscript start-stop-daemon

TARGET = $(BIN_TARGETS) $(SBIN_TARGETS)

all: $(TARGET)

consoletype: consoletype.c
	$(LD) $(CFLAGS) $(LDFLAGS) -o $@ $^

runscript: runscript.c
	$(LD) $(CFLAGS) $(LDFLAGS) -o $@ $^ -ldl

start-stop-daemon: start-stop-daemon.c
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ -DHAVE_ERROR_H -DHAVE_TIOCNOTTY -DHAVE_SETSID $^

install: $(TARGET)
	install -m 0755 -d $(DESTDIR)/bin
	install -m 0755 -d $(DESTDIR)/sbin
#	install -m 0755 $(BIN_TARGETS) $(DESTDIR)/bin
	install -m 0755 $(SBIN_TARGETS) $(DESTDIR)/sbin

clean:
	rm -f $(TARGET)
	rm -f *.o *~ core
