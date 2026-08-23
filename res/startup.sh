#!/bin/sh
# This file is executed when starting Sakura (before the TTY is taken control of)
# Custom startup code can be placed in this file or the start_cmd var can be
# pointed to a different file

# FreeBSD's vt(4) console can be tuned with vidcontrol(1) before Sakura draws
# over it. Uncomment the example below to load a larger console font, which is
# useful on HiDPI screens. Available fonts live in /usr/share/vt/fonts.
#
# if [ "$TERM" = "xterm" ] && [ -c /dev/ttyv0 ]; then
# 	vidcontrol -f /usr/share/vt/fonts/terminus-b32.fnt < /dev/console
# fi
