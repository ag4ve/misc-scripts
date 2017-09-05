#!/usr/bin/env bash

# $Id: tmux-start.sh,v 1.16 2015/11/01 22:16:34 swilson Exp $

# Author: Shawn Wilson <swilson@korelogic.com>
# Copyright 2015 Korelogic Inc. https://www.korelogic.com
# GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007
# http://www.gnu.org/licenses/gpl-3.0.html

# basename
script="${0##*/}"

IFS="." read -a bash_version <<<"${BASH_VERSION}"

die()
{
  echo -ne "$@" >&2
  exit 1
}

warn()
{
  echo "WARN: $@\n" >&2
}

debug()
{
  if [ -n "$DEBUG" ] ; then
    warn "$@"
  fi
}

opthelp()
{
  die "$@\n" \
    "$script [OPTIONS]\n" \
    "   -a    string to append to the command for each variable\n" \
    "   -c    command to run\n" \
    "   -f    force (restarts session with the same name)\n" \
    "   -n    name of the array to use\n" \
    "   -p    prefix to insert into the tmux session name\n" \
    "   -P    Pause between commands\n" \
    "   -r    Max retries per command\n" \
    "   -s    sourced config file with array of variables (warning: " \
      "contains code)\n" \
    "   -S    interactive shell (eg: bash --norc --noprofile)\n" \
    "   -x    run each element as a full command\n" \
    "   -d    debuging\n" \
    "   -h    this message\n"
}

session_test ()
{
  local session="$@"

  tmux list-window -t "$session" 2>/dev/null | wc -l
}

# Will be exported to every session that is started
_rerun_cmd ()
{
  local cmd="$1"
  if [[ -z "$cmd" ]] ; then
    return
  fi

  local max="$2"
  # Max needs to be defined just in case the command will never succeed
  if [[ -z "$max" ]] ; then
    max=10
  fi

  local sleep="$3"
  if [[ -z "$sleep" ]] ; then
    sleep=1
  fi

  local count=0
  while eval $cmd ; do
    if ((count >= max)) ; then
      break
    fi
    sleep "$sleep";
  done
}

config=~/.config/host-vars.sh

# Catch no options
if [[ "$#" -eq 0 ]] ; then
  opthelp
fi

# Default values
pause=0

while getopts ":a:n:c:fP:p:r:S:s:xdh" opt; do
  case "$opt" in
    # Append string
    a)
      append="${OPTARG}"
      ;;
    # Command
    c)
      cmd="${OPTARG}"
      ;;
    # Force a kill and respawn of a session with the same name
    f)
      force=1
      ;;
    # Variable name
    n)
      name="${OPTARG}"
      ;;
    # Pause value
    P)
      pause="${OPTARG}"
      ;;
    # Tmux session name prefix
    p)
      prefix="${OPTARG}"
      ;;
    # Max retries
    r)
      retries="${OPTARG}"
      ;;
    # Shell
    S)
      shell="${OPTARG}"
      ;;
    # Config file
    s)
      [[ -e "${OPTARG}" ]] || die "Config file [${OPTARG}] not found."
      config="${OPTARG}"
      ;;
    # No command eval
    x)
      nocmd=1
      ;;
    # Debug
    d)
      debug=1
      ;;
    # Help
    h)
      opthelp
      ;;
    *)
      opthelp
      ;;
  esac
done
shift $((OPTIND-1))

# Make sure we know if nothing is specified to be run
if [[ -z "$cmd" && -z "$nocmd" ]] ; then
  die "The -x option must be specified if not giving a command.\n"
fi

# Check proper command
if ! ( [[ -x "${cmd%% *}" ]] || type "${cmd%% *}" >/dev/null 2>&1 ) ; then
  die "Not a command [${cmd%% *}]\n"
else
  read -r acmd aparams <<<"${cmd}"
  fullcmd="$(type -p $acmd)"
  if [[ -n "$fullcmd" ]] ; then
    cmd="$fullcmd $aparams"
  else
    cmd="$acmd $aparams"
  fi
fi

# Sanity checks
if [ "${bash_version[0]}" -lt 4 ] ; then
  die "Bash version less than 4 is not supported\n"
fi
if ! type tmux >/dev/null 2>&1 ; then
  die "tmux does not exist\n"
fi

source "$config" 2>/dev/null

unset var
declare -n var="$name"

if [[ -z "$var" ]] ; then
  die "$name not defined in config [$config]\n"
else
  debug "Elements: ${var[@]}"
fi

if [[ -z "$shell" ]] ; then
  case "${SHELL##*/}" in
    bash)
      shell="bash --norc --noprofile"
      ;;
    zsh)
      shell="zsh -f -i"
      ;;
  esac
fi

offset=0
for ((count = 0 ; count < 10 ; count++)) ; do
  session="${prefix}${name}${count}"

  # Increment if the session name is already in use
  if [[ $(session_test "$session") -gt 0 ]] ; then
    if [[ -n "$force" ]] ; then
      tmux kill-session -t "$session"
    else
      continue
    fi
  fi

  # Create a new session - temporarily unset TMUX so it doesn't complain
  # if already inside tmux - -d makes this DWIM
  TMUX= tmux -2 new-session -d -s "$session"

  while [ $(session_test "$session") -eq 0 ] ; do
    sleep 1
  done

  # Make sure we only start 10 windows per session so meta-[0-9] work for
  # all windows
  if ((offset + 10 > ${#var[@]})) ; then
    max=$((${#var[@]} - $offset))
    end=1
  else
    max=10
  fi

  for ((num = 0 ; num < "$max" ; num++)) ; do
    # Window name
    unit="${var[${offset} + ${num}]}${append}"

    debug "Window name [$unit] Session [${session}:${num}]"

    # Start off with a new window
    if [[ "$num" -gt 0 ]] ; then
      tmux new-window -t "${session}:${num}" -n "$unit" -- "$shell"
    fi

    # Declare a private function to give commands (like ssh that might get
    # bogged down) a chance to start
    tmux send-keys -t "${session}:${num}" " $(declare -f _rerun_cmd)" C-m
    tmux send-keys -t "${session}:${num}" " clear" C-m
    tmux send-keys -t "${session}:${num}" "_rerun_cmd \"${cmd} ${unit}\" \"$retries\" \"$pause\"" C-m
  done

  # end when the array "var" is done
  if [[ -n "$end" ]] ; then
    break
  fi

  ((offset+=10))
done

