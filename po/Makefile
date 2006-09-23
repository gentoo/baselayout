initd_IN  := $(wildcard ../init.d/*)
sbin_IN   := $(filter-out %.patch,$(wildcard ../sbin/*))
ALL_IN    := $(initd_IN) $(sbin_IN)

localedir   := $(shell eval `grep '^svclib' ../sbin/functions.sh`; echo "$${svclib}/locale")
LINGUAS_ALL := $(patsubst %.po,%,$(wildcard *.po))
LINGUAS     ?= $(LINGUAS_ALL)
LINGUAS     := $(filter $(LINGUAS_ALL),$(LINGUAS))

all: $(LINGUAS:%=%.mo)

%.mo : %.po
	msgfmt --statistics -o $@ $<

%.po : rc-scripts.pot
	msgmerge --update $@ $^

rc-scripts.pot: $(ALL_IN)
	rm -f rc-scripts.pot; touch rc-scripts.pot
	for file in $+ ; do \
	       bash --dump-po-strings $$file \
	       | msguniq \
	       | msgcat --force-po -F - rc-scripts.pot -o rc-scripts.pot; \
	done

clean:
	rm -f *.mo *~

install: all
	for lang in $(LINGUAS); do \
		install -d $(DESTDIR)$(localedir)/$$lang/LC_MESSAGES ; \
		install -m 644 $$lang.mo \
			$(DESTDIR)$(localedir)/$$lang/LC_MESSAGES/rc-scripts.mo ; \
	done

.PHONY: all clean install
