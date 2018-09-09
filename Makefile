SHELL := /bin/bash
OS := $(if $(shell fgrep 'Microsoft@Microsoft.com' /proc/version),WSL,$(patsubst MSYS_NT%,MSYS_NT,$(shell uname -s)))
DIST := $(strip $(if $(filter Darwin,$(OS)),mac,\
	$(if $(filter MSYS_NT,$(OS)),msys,\
	$(if $(wildcard /etc/os-release),$(shell . /etc/os-release 2> /dev/null && echo $$ID),\
	$(shell cat /etc/system-release | cut -d' ' -f1 | tr '[:upper:]' '[:lower:]')))))
DOTFILES = vimrc vimrc.local gvimrc gvimrc.local screenrc tmux.conf bashrc profile pylintrc dircolors
DESTFILES = $(addprefix $(HOME)/.,$(DOTFILES)) $(addprefix $(HOME)/,$(wildcard bin/*))
VIMDIR = $(HOME)/.vim
AUTOLOADDIR = $(VIMDIR)/autoload
PLUGINRC = $(VIMDIR)/pluginrc.vim
PKGS := coreutils tmux curl python-setuptools clang
LOCALDIR = $(HOME)/.local/share
FONTDIR = $(HOME)/.local/share/fonts
FONTS = .fonts_installed
BRANCH = master
VPATH = dotfiles:snippets

all: install


ifneq ($(filter $(DIST),ubuntu debian deepin),)
include include/ubuntu.mk
else
PLUGGED = $(VIMDIR)/plugged
PKGS += ctags cmake ack

$(AUTOLOADDIR)/plug.vim:
	curl -fLo $@ --create-dirs https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

$(PLUGGED): $(AUTOLOADDIR)/plug.vim $(PLUGINRC)
	vim +PlugInstall +qall
	@touch $(PLUGGED)

ifeq ($(DIST),mac)
include include/mac.mk
endif
ifneq ($(filter $(DIST),fedora centos redhat),)
include include/redhat.mk
endif
ifeq ($(DIST),msys)
include include/msys.mk
endif
vimplug-update:
	vim +PlugUpgrade +PlugUpdate +qall

.SECONDEXPANSION:
$(PLUGINRC): vim/plugrc.vim $$(wildcard snippets/$$(OS).$$(@F)) $$(wildcard snippets/$$(DIST).$$(@F))
	mkdir -p $(dir $(PLUGINRC))
	@echo 'let g:plug_window = "vertical botright new"' > $@
	@echo 'call plug#begin()' >> $@
	cat $^ >> $@
	@echo 'call plug#end()' >> $@
endif


INPUTFONTS = $(shell find fonts/InputMono -name *.ttf -type f)
FONTDIRS = $(dir $(INPUTFONTS))
TARGETFONTS = $(filter-out $(wildcard $(FONTDIR)/*.ttf), \
	      $(addprefix $(FONTDIR)/,$(notdir $(INPUTFONTS))))

vpath %.ttf $(FONTDIRS)

ifeq ($(shell echo 'import sys; print([x for x in sys.path if "powerline_status" in x][0])' | python 2> /dev/null),)
PYMS += $(if $(filter powerline,$(INSTALLTARGETS)),,powerline-status)
endif
ifeq ($(shell echo 'import sys; print([x for x in sys.path if "psutil" in x][0])' | python 2> /dev/null),)
PYMS += $(if $(filter python-psutil,$(INSTALLTARGETS)),,$(if $(filter $(DIST),msys),,psutil))
endif
ifeq ($(shell echo 'import sys; print([x for x in sys.path if "pylint" in x][0])' | python 2> /dev/null),)
PYMS += $(if $(filter pylint,$(INSTALLTARGETS)),,pylint)
endif

$(PYMS): $(EZINSTALL) $(TARGETPKGS)
	mkdir -p ~/.local/lib/python$$(python -V 2>&1 | cut -d' ' -f2 | cut -d'.' -f-2)/site-packages
	easy_install $(if $(shell easy_install --help | fgrep -e '--user'),--user,--prefix ~/.local) $@

INSTALLPKGS = $(filter-out $(PYMS),$(INSTALLTARGETS))

$(HOME)/%vimrc.local:
	touch $@

$(HOME)/.vimrc: $(if $(filter-out MSYS_NT,$(OS)),set-tmpfiles.vimrc)
$(HOME)/.profile: $(if $(filter WSL MSYS_NT,$(OS)),auto-ssh-agent.profile)
$(HOME)/.tmux.conf: \
	$(if $(filter 16.04,$(UBUNTU_VER)),vi-style-2.1.tmux.conf,vi-style.tmux.conf) \
	$(if $(filter powerline,$(INSTALLTARGETS)),$(if \
	$(filter ubuntu debian deepin,$(DIST)),ubuntu.tmux.conf), pym-powerline.tmux.conf)

dotfiles/dircolors: LS_COLORS/LS_COLORS
	ln -f $< $@

LS_COLORS/LS_COLORS:
	git clone -b $(BRANCH) https://github.com/trapd00r/LS_COLORS.git $(dir $@)

update-LS_COLOR:
	git -C $(@:update-%=%) pull origin $(BRANCH)
 
snippets/pym-powerline.tmux.conf: $(filter powerline-status,$(PYMS))
	echo source \"$$(echo 'import sys; print([x for x in sys.path if "powerline_status" in x][0])' \
		| python)/powerline/bindings/tmux/powerline.conf\" > $@

.SECONDEXPANSION:
$(HOME)/.%: $$(wildcard snippets/$$(OS)$$(@F)) $$(wildcard snippets/$$(DIST)$$(@F)) %
	@if [ -h $@ ] || [[ -f $@ && "$$(stat -c %h -- $@ 2> /dev/null)" -gt 1 ]]; then rm -f $@; fi
	@if [ "$(@F)" = ".$(notdir $^)" ]; then \
		echo "ln -f $< $@"; \
		ln -f $< $@; else \
		echo "cat $^ > $@"; \
		cat $^ > $@; fi

$(HOME)/bin/:
	install -m 0755 -d $@

$(HOME)/bin/%: bin/% | $(HOME)/bin/
	install -m 0755 $< $@

fonts/powerline-fonts/:
	git clone -b master https://github.com/powerline/fonts.git $@

$(FONTDIR)/:
	mkdir -p $@

$(FONTDIR)/%.ttf: %.ttf | $(FONTDIR)/
	install -m 0644 $< $@

$(TARGETFONTS): $(TARGETPKGS)

.fonts_installed: fonts/powerline-fonts/ $(TARGETFONTS)
	fonts/powerline-fonts/install.sh && touch $@

fonts-update: fonts/powerline-fonts/
	@if ! LANGUAGE=en.US_UTF-8 git -C $< pull origin master | tail -1 | fgrep 'Already up'; then \
		$</install.sh; fi

$(TARGETPKGS): install-pkgs

ifneq ($(wildcard $(HOME)/.bash_profile),)
DESTFILES += del-bash_profile
endif

del-bash_profile:
	mv -iv $(HOME)/.bash_profile $(HOME)/.bash_profile.old

install: $(DESTFILES) $(TARGETPKGS) $(PKGPLUGINTARGETS) $(GITTARGETS) $(PLUGINRC) $(PLUGGED) $(PYMS) $(FONTS)

update: install vimplug-update $(patsubst %,fonts-update,$(filter-out msys,$(DIST)))

uninstall:
	-rm -fr $(DESTFILES) $(GITTARGETS) $(PLUGINRC) $(PLUGGED) $(BUNDLE) $(AUTOLOADDIR)/plug.vim $(FONTS)

debug:
	@echo PKGS: $(PKGS)
	@echo INSTALLPKGS: $(INSTALLPKGS)
	@echo INSTALLTARGETS: $(INSTALLTARGETS)
	@echo TARGETPKGS: $(TARGETPKGS)

.PHONY: all install install-pkgs uninstall update del-bash_profile vimplug-update fonts-update \
	$(TARGETPKGS) $(PYMS) $(EZINSTALL)
