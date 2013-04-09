
root     = $(srcroot)/dist
srcroot  = $(CURDIR)
userfile = $(HOME)/.leela-server.makefile

include $(srcroot)/makefile.lib

SRC_HASKELL = $(shell $(bin_find) $(srcroot)/src/dmproc -type f -name \*.hs)
TRY_HASKELL = $(shell $(bin_find) $(srcroot)/try/dmproc -type f -name \*.hs)

bootstrap: .saverc
	test -d $(HOME)/pyenv/leela-server || $(bin_virtualenv) $(HOME)/pyenv/leela-server
	$(HOME)/pyenv/leela-server/bin/pip install -q -r $(srcroot)/pip-requires.txt
	$(HOME)/pyenv/leela-server/bin/pip install -q nose
	$(HOME)/pyenv/leela-server/bin/pip install -q mock
	$(bin_cabal) update
	$(bin_cabal) install -v0 -O2 attoparsec
	$(bin_cabal) install -v0 -O2 vector
	$(bin_cabal) install -v0 -O2 blaze-builder
	$(bin_cabal) install -v0 -O2 double-conversion
	$(bin_cabal) install -v0 -O2 regex-tdfa
	$(bin_cabal) install -v0 -O2 stm
	$(bin_cabal) install -v0 -O2 quickcheck
	$(bin_cabal) install -v0 -O2 hslogger
	$(bin_cabal) install -v0 -O2 hspec
	$(bin_cabal) install -v0 -O2 shelltestrunner

clean:
	$(call .check_bin,find)
	$(bin_find) . -type f -name \*.o -exec rm -f \{\} \;
	$(bin_find) . -type f -name \*.hi -exec rm -f \{\} \;
	$(bin_find) . -type f -name \*.pyc -exec rm -f \{\} \;
	$(bin_find) . -type f -name \*.hi -exec rm -f \{\} \;
	rm -f ./src/dmproc/DarkMatter/dmproc ./try/dmproc/dmtry

compile-dmtry: $(srcroot)/try/dmproc/dmtry

compile-dmproc: $(srcroot)/src/dmproc/DarkMatter/dmproc $(srcroot)/src/dmproc/DarkMatter/timeline $(srcroot)/src/dmproc/DarkMatter/multicast

test-dmproc: compile-dmtry
	$(srcroot)/try/dmproc/dmtry

test-server:
	$(call .check_bin,python)
	env $(pyenv) $(bin_nosetests) $(nosetestsargs) $(srcroot)/try/server

test: test-dmproc test-server

test-smoke:
	$(call .check_bin,lsof)
	$(call .check_bin,python)
	$(call .check_bin,shelltest)
	$(call .check_bin,twistd)
	$(call .check_bin,socat)
	$(call .check_bin,curl)
	$(call .check_bin,date)
	$(call .check_bin,sed)
	env $(pyenv) CHDIR=$(srcroot)/dist $(srcroot)/dist/etc/init.d/leela stop >/dev/null
	env $(pyenv) CHDIR=$(srcroot)/dist $(srcroot)/dist/etc/init.d/leela start >/dev/null
	cd $(srcroot); env $(pyenv) \
                           $(bin_shelltest) $(shelltestargs) -c $(shelltestpath) -- --timeout=60
	@env $(pyenv) CHDIR=$(srcroot)/dist $(srcroot)/dist/etc/init.d/leela stop >/dev/null

dist-build: compile-dmproc

dist-clean:
	if [ -n "$(root)" -a "$(root)" != "/" ]; then rm -r -f "$(root)"; fi

dist-install: python_sitelib=$(shell $(bin_python) -c "from distutils.sysconfig import get_python_lib; print(get_python_lib());")
dist-install:
	$(call check_bin,install)
	$(call check_bin,find)
	$(call check_bin,python)
	mkdir -p $(root)/usr/bin
	mkdir -p $(root)/usr/libexec
	mkdir -p $(root)/etc/default
	mkdir -p $(root)/var/run/leela
	mkdir -p $(root)/var/log/leela
	mkdir -p $(root)/etc/init.d
	$(bin_python) setup.py -q install --root=$(root)
	$(bin_install) -m 0755 $(srcroot)/src/dmproc/DarkMatter/dmproc $(root)/usr/bin
	$(bin_install) -m 0755 $(srcroot)/src/dmproc/DarkMatter/timeline $(root)/usr/bin
	$(bin_install) -m 0755 $(srcroot)/src/dmproc/DarkMatter/multicast $(root)/usr/bin
	for f in $(srcroot)/etc/default/*                          \
                 $(srcroot)/etc/leela.conf;                        \
	do                                                         \
	  $(bin_install) -m 0600 $$f $(root)/$${f#$(srcroot)/};    \
	done
	for f in $(srcroot)/etc/init.d/*                           \
                 $(srcroot)/usr/libexec/*;                         \
        do                                                         \
          $(bin_install) -m 0755 $$f $(root)/$${f#$(srcroot)/};    \
        done
	$(bin_sed) -i 's,\$${__ENVIRON__},PYTHONPATH="$$PYTHONPATH:$(root)/$(python_sitelib)" CHDIR="$(root)",g' $(root)/usr/libexec/leela-interact
	$(bin_sed) -i 's,\$${bin_python:-python},$(bin_python),g' $(root)/usr/libexec/leela-interact

$(srcroot)/src/dmproc/DarkMatter/dmproc: $(SRC_HASKELL)
	$(call .check_bin,ghc)
	$(bin_ghc) $(ghcargs) -rtsopts -v0 -W -Wall -fforce-recomp -threaded -i$(srcroot)/src/dmproc -O2 --make -static -optc-static -optl-static $@.hs -optl-pthread

$(srcroot)/src/dmproc/DarkMatter/timeline: $(SRC_HASKELL)
	$(call .check_bin,ghc)
	$(bin_ghc) $(ghcargs) -rtsopts -v0 -W -Wall -fforce-recomp -threaded -i$(srcroot)/src/dmproc -O2 --make -static -optc-static -optl-static $@.hs -optl-pthread

$(srcroot)/src/dmproc/DarkMatter/multicast: $(SRC_HASKELL)
	$(call .check_bin,ghc)
	$(bin_ghc) $(ghcargs) -rtsopts -v0 -W -Wall -fforce-recomp -i$(srcroot)/src/dmproc -O2 --make -static -optc-static -optl-static $@.hs -optl-pthread

$(srcroot)/try/dmproc/dmtry: $(SRC_HASKELL) $(TRY_HASKELL)
	$(call .check_bin,ghc)
	$(call .check_bin,dash)
	env bin_dash=$(bin_dash) $(bin_ghc) $(ghcargs) -rtsopts -v0 -i$(srcroot)/src/dmproc -i$(srcroot)/try/dmproc -O2 --make $@.hs

%: %.test
	$(MAKE) $(MAKEARGS) test-smoke shelltestpath=$^

.SUFFIXES: .test .hs
