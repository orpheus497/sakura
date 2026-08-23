#!/bin/sh
# Shell environment setup after login
# Copyright (C) 2015-2016 Pier Luigi Fiorini <pierluigi.fiorini@gmail.com>

# This file is extracted from kde-workspace (kdm/kfrontend/genkdmconf.c)
# Copyright (C) 2001-2005 Oswald Buddenhagen <ossi@kde.org>

# Copyright (C) 2024 The Fairy Glade
# This work is free. You can redistribute it and/or modify it under the
# terms of the Do What The Fuck You Want To Public License, Version 2,
# as published by Sam Hocevar. See the LICENSE file for more details.

# On FreeBSD the base system keeps its shell startup files in /etc, while
# shells and X11 installed from ports keep theirs under the prefix (usually
# /usr/local/etc, substituted below as CONFIG_DIRECTORY). Both are sourced,
# base first, so that a ports-installed file can override the base one.
BASE_CONFIG_DIRECTORY=/etc

# Note that the respective logout scripts are not sourced.
case $SHELL in
*/bash)
    [ -z "$BASH" ] && exec $SHELL "$0" "$@"
    set +o posix
    [ -f "$BASE_CONFIG_DIRECTORY"/profile ] && . "$BASE_CONFIG_DIRECTORY"/profile
    [ -f "$CONFIG_DIRECTORY"/profile ] && . "$CONFIG_DIRECTORY"/profile
    if [ -f "$HOME"/.bash_profile ]; then
        . "$HOME"/.bash_profile
    elif [ -f "$HOME"/.bash_login ]; then
        . "$HOME"/.bash_login
    elif [ -f "$HOME"/.profile ]; then
        . "$HOME"/.profile
    fi
    ;;
*/zsh)
    [ -z "$ZSH_NAME" ] && exec $SHELL "$0" "$@"
    # The zsh port is built with --enable-etcdir=$CONFIG_DIRECTORY
    [ -d "$CONFIG_DIRECTORY"/zsh ] && zdir="$CONFIG_DIRECTORY"/zsh || zdir="$CONFIG_DIRECTORY"
    zhome=${ZDOTDIR:-"$HOME"}
    # zshenv is always sourced automatically.
    [ -f "$zdir"/zprofile ] && . "$zdir"/zprofile
    [ -f "$zhome"/.zprofile ] && . "$zhome"/.zprofile
    [ -f "$zdir"/zlogin ] && . "$zdir"/zlogin
    [ -f "$zhome"/.zlogin ] && . "$zhome"/.zlogin
    emulate -R sh
    ;;
*/csh|*/tcsh)
    # [t]cshrc is always sourced automatically.
    # Note that sourcing csh.login after .cshrc is non-standard.
    # /etc/csh.login is part of the FreeBSD base system.
    sess_tmp=$(mktemp /tmp/sess-env-XXXXXX)
    $SHELL -c "if (-f $BASE_CONFIG_DIRECTORY/csh.login) source $BASE_CONFIG_DIRECTORY/csh.login; if (-f $CONFIG_DIRECTORY/csh.login) source $CONFIG_DIRECTORY/csh.login; if (-f ~/.login) source ~/.login; /bin/sh -c 'export -p' >! $sess_tmp"
    . "$sess_tmp"
    rm -f "$sess_tmp"
    ;;
*/fish)
    [ -f "$BASE_CONFIG_DIRECTORY"/profile ] && . "$BASE_CONFIG_DIRECTORY"/profile
    [ -f "$CONFIG_DIRECTORY"/profile ] && . "$CONFIG_DIRECTORY"/profile
    [ -f "$HOME"/.profile ] && . "$HOME"/.profile
    sess_tmp=$(mktemp /tmp/sess-env-XXXXXX)
    $SHELL --login -c "/bin/sh -c 'export -p' > $sess_tmp"
    . "$sess_tmp"
    rm -f "$sess_tmp"
    ;;
*) # Plain sh, ksh, and anything we do not know.
    [ -f "$BASE_CONFIG_DIRECTORY"/profile ] && . "$BASE_CONFIG_DIRECTORY"/profile
    [ -f "$CONFIG_DIRECTORY"/profile ] && . "$CONFIG_DIRECTORY"/profile
    [ -f "$HOME"/.profile ] && . "$HOME"/.profile
    ;;
esac

if [ "$XDG_SESSION_TYPE" = "x11" ]; then
    [ -f "$CONFIG_DIRECTORY"/xprofile ] && . "$CONFIG_DIRECTORY"/xprofile
    [ -f "$HOME"/.xprofile ] && . "$HOME"/.xprofile

    # Run all system xinitrc shell scripts. The xinit port installs these under
    # the prefix, i.e. $CONFIG_DIRECTORY/X11/xinit/xinitrc.d.
    if [ -d "$CONFIG_DIRECTORY"/X11/xinit/xinitrc.d ]; then
        for i in "$CONFIG_DIRECTORY"/X11/xinit/xinitrc.d/* ; do
            if [ -x "$i" ]; then
                . "$i"
            fi
        done
    fi

    export USERXSESSION="$HOME"/.xsession
    export USERXSESSIONRC="$HOME"/.xsessionrc
    export ALTUSERXSESSION="$HOME"/.Xsession

    if [ -f "$USERXSESSION" ]; then
        . "$USERXSESSION"
    fi

    if [ -d "$CONFIG_DIRECTORY"/X11/Xresources ]; then
        for i in "$CONFIG_DIRECTORY"/X11/Xresources/*; do
            [ -f "$i" ] && xrdb -merge "$i"
        done
    elif [ -f "$CONFIG_DIRECTORY"/X11/Xresources ]; then
        xrdb -merge "$CONFIG_DIRECTORY"/X11/Xresources
    fi
    [ -f "$HOME"/.Xresources ] && xrdb -merge "$HOME"/.Xresources
    [ -f "$XDG_CONFIG_HOME"/X11/Xresources ] && xrdb -merge "$XDG_CONFIG_HOME"/X11/Xresources
fi

exec "$@"
