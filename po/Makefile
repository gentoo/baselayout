initd_IN := \
	bootmisc checkfs checkroot clock consolefont domainname halt.sh \
	hostname keymaps local localmount modules netmount numlock \
	reboot.sh rmnologin shutdown.sh urandom

sbin_IN := \
	rc-update depscan.sh env-update.sh modules-update \
	init-common-post.sh init-common-pre.sh init-functions.sh \
	init.bsd.sh init.linux.sh \
	functions.sh runscript.sh rc \
	rc-daemon.sh rc-help.sh rc-services.sh

localedir      := /usr/share/locale
LINGUAS        :=

all: $(LINGUAS:%=%.mo)

%.mo : %.po
	msgfmt --statistics -o $@ $<

%.po : rc-scripts.pot
	msgmerge --update $@ $^

rc-scripts.pot: $(initd_IN:%=../init.d/%) $(sbin_IN:%=../sbin/%)
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
	       install -d $(localedir)/$$lang/LC_MESSAGES ; \
	       install -m 644 $$lang.mo \
	               $(localedir)/$$lang/LC_MESSAGES/rc-scripts.mo ; \
	done

.PHONY: install clean all

