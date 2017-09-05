#!/bin/bash

controlfile="~/.ssh/control-${USER}\@${1}"
if [ -e "$controlfile" ] ; then
    rm -f "$controlfile"
fi
ssh "$@" -t bash -c "
    if { ! tput longname && tput -T "${TERM%-*}" longname; } >/dev/null 2>&1
        then export TERM="${TERM%-*}"
    fi
    screen -ddR
"
