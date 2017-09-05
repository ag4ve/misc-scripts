#!/usr/bin/env bash

# $Id: mon-hosts.sh,v 1.46 2015/12/12 18:22:24 swilson Exp $

# Author: Shawn Wilson <swilson@korelogic.com>
# Copyright 2015 Korelogic Inc. https://www.korelogic.com
# GNU GENERAL PUBLIC LICENSE Version 3, 29 June 2007
# http://www.gnu.org/licenses/gpl-3.0.html

# A bash script to show the status of a group or groups of hosts based on a
# config file and command-line parameters. An command (based on the example
# config) might look like: 
# mon-hosts -l foo,bar", or "mon-hosts -l everything -a 'uname -r' -R".

# Example file:
# #!/bin/bash -
# 
# # create a list named "foo"
# foo=()
# foo+=(perlish)
# foo+=(tester)
# 
# # create another list named "bar"
# bar=()
# bar+=(nibble)
# bar+=(osx)
# 
# # a list containing all elements from foo and bar
# everything=()
# everything+=(${foo[*]})
# everything+=(${bar[*]})

# Test by creating/removing a local file (foo) to show foo as up/down:
# ./mon-hosts -c 'test -e' -a '' -s /dev/null -l foo
# Or to check if a host is up by pinging:
# ./mon-hosts.sh -c 'ping -c 1' -a '>/dev/null 2>&1' -s /dev/null -l 10.0.0.1
# Command line IP ping scan (takes a while - don't do this - the use of ping 
# is for interoperability with all Unices):
# ips=(10.0.0.{1..20}) && export exported=$(declare -p ips) && ./mon-hosts.sh -c 'ping -c 1 -w 1 -W 1' -a '>/dev/null 2>&1' -s /dev/null -l ips -e

# Default values
append="echo -n"
cmd="ssh"
up="*"
down="X"
pause=5
sleep=1
retries=1
usereturn=0
config=~/.config/host-vars.sh
cols=1
minwidth=15
datefmt="%c"

set -o nounset
# set -eix

# Make sure we're using a sane locale
export LANG=C

# basename
script="${0##*/}"

# bash-libs needs to be in your path - also see bashpack
source msg-handling.sh

# Try to rerun a command until it succeeds or a limit it hit
rerun_cmd ()
{
  debug 6 "rerun_cmd options [$@]"

  unset rerun_cmd_ret
  declare -ga rerun_cmd_ret

  declare cmd="${1:-}"
  declare host="${2:-}"
  declare append="${3:-}"
  declare max="${4:-1}"
  declare sleep="${5:-0}"

  if [[ -z "${cmd:-}" || -z "${host:-}" ]] ; then
    return
  fi

  declare fullcmd="$cmd $host $append 2>/dev/null"
  declare origup="$up"

  # If we're returning command data from the host
  # $up is the return data from the command in this case
  if (( usereturn != 0 )) ; then
    declare up=""
    fullcmd="up=\"\$($fullcmd)\""
  fi
  debug 4 "rerun_cmd fullcmd [$fullcmd]"

  for (( count = 0 ; count < max ; count++ )) ; do
    if eval $fullcmd ; then
      break
    fi
    sleep "${sleep:-0}"
  done
  debug 5 "rerun_cmd count [$count] max [$max] up [$up] down [$down]"

  # Determine status
  if (( count < max )) ; then
    # Make sure there's something to return
    if [[ -z "${up:-}" ]] ; then
      up="$origup"
    fi

    rerun_cmd_ret=("$host" "[$up]")
  else
    rerun_cmd_ret=("$host" "[$down]")
    if [[ -n "${bell:-}" ]] ; then
      echo -ne "\a"
    fi
  fi

  debug 4 "rerun_cmd_ret [${rerun_cmd_ret[@]:-}]"
}

# Format host data
host_print()
{
  debug 6 "host_print options [$@]"

  if [[ -z "${1:-}" ]] ; then
    return
  fi

  declare -n status="${1:-}"
  declare group="${2:-}"
  declare cols="${3:-1}"

  # Calculate widths 

  declare maxhost=0
  declare maxupdown=0

  # Determine the maximum width of hosts and status value
  for ((count = 0 ; count < "${#status[@]:-}" ; count+=2)) ; do
    hostlength="${#status[$count]}"
    debug 7 "host [${status[$count]}] length [$hostlength]"
    if (( hostlength > maxhost )) ; then
      maxhost="$hostlength"
    fi
    if [[ -n "${usereturn:-}" ]] ; then
      updownlength="${#status[$count +1]}"
      debug 7 "updown [${status[$count +1]}] length [$updownlength]"
      if (( updownlength > maxupdown )) ; then
        maxupdown="$updownlength"
      fi
    fi
  done
  debug 5 "host_print maxhost length [$maxhost]"

  for i in "${#up}" "${#down}" ; do
    if (( i > maxupdown )) ; then
      maxupdown="$i"
    fi
  done
  debug 5 "host_print maxupdown length [$maxupdown]"

  # Make sure lengths aren't greater than the maxes or mins and that the
  # max/min value wouldn't be greater or less than their current value
  # if they are host  gets 75% of the width and status gets 25%
  if [[ -n "${maxwidth:-}" ]] && (( (maxhost + maxupdown) > maxwidth )) ; then
    declare tmaxhost=$(( (maxwidth / 4) * 3))
    if (( tmaxhost < maxhost )) ; then
      maxhost="${tmaxhost:-}"
    fi
    declare tmaxupdown=$(( (maxwidth / 4) * 1))
    if (( tmaxupdown < maxupdown )) ; then
      maxupdown="${tmaxupdown:-}"
    fi
    debug 5 "host_print length max reset: maxhost [$maxhost] maxupdown [$maxupdown]"
  fi
  if [[ -n "${minwidth:-}" ]] && (( (maxhost + maxupdown) < minwidth )) ; then
    declare tmaxhost=$(( (minwidth / 4) * 3))
    if (( tmaxhost > maxhost )) ; then
      maxhost="${tmaxhost:-}"
    fi
    declare tmaxupdown=$(( (minwidth / 4) * 1))
    if (( tmaxupdown > maxupdown )) ; then
      maxupdown="${tmaxupdown:-}"
    fi
    debug 5 "host_print length min reset: maxhost [$maxhost] maxupdown [$maxupdown]"
  fi
  if [[ -n "${minstatus:-}" ]] && (( maxupdown < minstatus )) ; then
    maxupdown="$minstatus"
    debug 5 "host_print length minstatus reset: maxupdown [$maxupdown]"
  fi

  # Calculate the number of columns that fit on a line
  # <allowed colunms> = 
  # <terminal space> / <hostname space> + <status space> + <added whitespace>
  declare colnum=$(( $cols / ($maxhost + $maxupdown +3) ))
  if (( colnum < 1 )) ; then
    colnum=1
  fi
  debug 4 "host_print colnum [$colnum] cols [$cols]"

  # Print a group if it's defined
  if [[ -n "${group:-}" ]] ; then
    host_print_ret="${host_print_ret}${group}\n "
  fi

  # Loop through data and properly format it
  declare newline=1
  for ((count = 0 ; count < "${#status[@]}" ; count+=2)) ; do
    # Determine if we need a line break
    if (( newline == 0 && ((count / 2) % colnum) == 0 )) ; then
      host_print_ret="$host_print_ret\n "
      newline=1
    fi

    # Set pad if required (one space is applied by default): 
    # <max field number> - <length of variable> + <space>
    declare hostpad=$(( maxhost - ${#status[$count]} +1 ))
    if (( hostpad < 0 )) ; then
      hostpad=1
    fi
    declare updownpad=$(( maxupdown - ${#status[$count +1]} +1 ))
    if (( updownpad < 0 )) ; then
      updownpad=1
    fi

    # Append formatted line part to return variable
    printf -v host_print_ret \
      "%s%.${maxhost}s%-${hostpad}s%.${maxupdown}b%-${updownpad}s" \
      "$host_print_ret" \
      "${status[$count]}" \
      " " \
      "${status[$count +1]}" \
      " "

    newline=0
  done

  # A newline won't have been appended
  host_print_ret="$host_print_ret\n"

  # Only add a separating line if hosts were printed
  if [[ "$group\n" != "$host_print_ret" ]] ; then
    host_print_ret="${host_print_ret}${line}\n"
  fi
}

# Do work for each host or group of hosts
eval_host()
{
  declare hoststr="${1:-}"
  declare hostvar
  declare hostcmd
  IFS="=" read hostvar hostappend <<<"${hoststr:-}"
  # Make sure hostvar is defined and a valid variable name
  if [[ -n "${hostvar:-}" && $hostvar =~ ^[a-zA-Z_][a-zA-Z_0-9]*$ ]] ; then
    declare -n var="$hostvar"
  fi
  # If there's no individual <hosts>=<cmd> use the default append command
  if [[ -z "${hostappend:-}" ]] ; then
    hostappend="${append:-}"
  fi
  
  debug 5 "hostvar [$hostvar] var [" $(declare -p var 2>/dev/null) "]"
  # The hostvar is not in the config so hostvar should be a hostname
  if [[ -z "${var:-}" ]] ; then
    rerun_cmd "$cmd" "$hostvar" "$hostappend" "${retries:-}" "${sleep:-}"
    host_print "rerun_cmd_ret" "$cols"
    if [[ -n "${changefile:-}" ]] ; then
        data+=("${rerun_cmd_ret[@]:-}")
    fi
    unset rerun_cmd_ret
  # This should be the default - hostvar is defined
  else
    declare -a statushosts
    for host in "${var[@]}" ; do
      rerun_cmd "$cmd" "$host" "$hostappend" "${retries:-}" "${sleep:-}"
      statushosts+=("${rerun_cmd_ret[0]:-}")
      statushosts+=("${rerun_cmd_ret[1]:-}")
    done
    host_print "statushosts" "$hostvar" "$cols"
    if [[ -n "${changefile:-}" ]] ; then
        data+=("${statushosts[@]:-}")
    fi
    unset statushosts
  fi
}

opthelp()
{
  die "$@\n" \
    "$script [OPTIONS]\n" \
    "   -a    String to append to the command (default: echo -n)\n" \
    "   -b    Audible bell when hosts are down (default: no)\n" \
    "   -c    Command to run (default: ssh)\n" \
    "   -C    Do not clear between runs (default: no)\n" \
    "   -e    Eval an \$exported variable (default: no)\n" \
    "   -F    Date format (default: %c)\n" \
    "   -l    Comma separated list of hosts or arrays of hosts and optional" \
      "individual commands (required:" \
      "host0[=<cmd>],host1[=<cmd>],...hostn[=<cmd>])\n" \
    "   -n    Number of runs (default: infinite)\n" \
    "   -m    Down mark (default: [X])\n" \
    "   -M    Up mark (default: [*])\n" \
    "   -p    Pause between runs (default: 5)\n" \
    "   -P    Pause between retries (default: 1)\n" \
    "   -r    Max retries per command (default: 1)\n" \
    "   -R    Use the return value instead of the up value (default: no)\n" \
    "   -s    Sourced config file with array of variables (warning:" \
      "contains code, default: ~/.config/host-vars.sh)\n" \
    "   -S    Status change file (default: none)\n" \
    "   -w    Max total column (name and status) width (default: none)\n" \
    "   -W    Min total column (name and status) width (default: 15)\n" \
    "   -X    Min status width (default: none)\n" \
    "   -d    Debug level (default: 0)\n" \
    "   -D    Debug file (default: none)\n" \
    "   -h    This message\n"
}

while getopts ":a:bc:CeF:l:m:M:n:p:P:r:Rs:S:w:W:X:d:D:h" opt; do
  case "$opt" in
    # Append string
    a)
      append="${OPTARG}"
      ;;
    # Bell
    b)
      bell=1
      ;;
    # Command
    c)
      cmd="${OPTARG}"
      ;;
    # Do not clear
    C)
      noclear=1
      ;;
    # Exported variable name
    e)
      exports=1
      ;;
    # Date format
    F)
      datefmt="${OPTARG}"
      ;;
    # Host list
    l)
      IFS="," read -a hosts <<<"${OPTARG}"
      ;;
    # Down mark
    m)
      down="${OPTARG}"
      ;;
    # Up mark
    M)
      up="${OPTARG}"
      ;;
    # Number of runs
    n)
      [[ "${OPTARG}" == [0-9]* ]] || die "-n should be an integer\n"
      runs="${OPTARG}"
      ;;
    # Pause time
    p)
      [[ "${OPTARG}" == [0-9]* ]] || die "-p should be an integer\n"
      pause="${OPTARG}"
      ;;
    # Max retries
    r)
      [[ "${OPTARG}" == [0-9]* ]] || die "-r should be an integer\n"
      retries="${OPTARG}"
      ;;
    # Use return value
    R)
      usereturn=1
      ;;
    # Config file
    s)
      [[ -e "${OPTARG}" ]] || die "Config file [${OPTARG}] not found\n"
      config="${OPTARG}"
      ;;
    # Status change file
    S)
      [[ ( -n "${OPTARG%/*}" && -w "${OPTARG%/*}/." ) || -w "./." ]] || die \
        "Can not write change file [${OPTARG}]\n"
      changefile="${OPTARG}"
      ;;
    # Max cel width
    w)
      [[ "${OPTARG}" == [0-9]* ]] || die "-w should be an integer\n"
      maxwidth="${OPTARG}"
      ;;
    # Min col width
    W)
      [[ "${OPTARG}" == [0-9]* ]] || die "-W should be an integer\n"
      minwidth="${OPTARG}"
      ;;
    # Min status width
    X)
      [[ "${OPTARG}" == [0-9]* ]] || die "-X should be an integer\n"
      minstatus="${OPTARG}"
      ;;
    # Debug
    d)
      debug="${OPTARG}"
      ;;
    # Debug file
    D)
      debug_file="${OPTARG}"
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

debug 3 "append [${append:-}]"
debug 3 "bell [${bell:-}]"
debug 3 "cmd [${cmd:-}]"
debug 3 "noclear [${noclear:-}]"
debug 3 "datefmt [${datefmt:-}]"
debug 3 "hosts [${hosts[@]:-}]"
debug 3 "down [${down:-}]"
debug 3 "up [${up:-}]"
debug 3 "pause [${pause:-}]"
debug 3 "retries [${retries:-}]"
debug 5 "usereturn [${usereturn:-}]"
debug 3 "config [${config:-}]"
debug 3 "changefile [${changefile:-}]"
debug 3 "maxwidth [${maxwidth:-}]"
debug 3 "minwidth [${minwidth:-}]"
debug 3 "minstatus [${minstatus:-}]"
debug 3 "debug [${debug:-}]"
debug 3 "debug_file [${debug_file:-}]"

date="date +${datefmt:-}"

# Make sure hosts were given
if [[ -z "${hosts[@]:-}" ]] ; then
  opthelp "No hosts defined\n"
fi

# Get config data
if ! source "$config" 2>/dev/null ; then
  die "Config file [$config] does not exist\n"
fi

# Check for the command
if ! type "${cmd%% *}" >/dev/null 2>&1 ; then
  die "[$cmd] does not exist\n"
fi

# Eval command line variable if it exists
if [[ -n "${exports:-}" ]] ; then
  eval "$exported" 2>/dev/null
fi

# Main loop
runcount=0
declare -a olddata=()
while true ; do
  debug 6 "Main loop"
  sdate=$($date)
  ((runcount++))
  declare host_print_ret=""

  # Try to define a line that spans the terminal
  # doing this here allows for terminal resize between runs
  if type tput >/dev/null 2>&1 ; then
    oldcols="${cols:-}"
    cols=$(tput cols)
    debug 6 "Terminal cols: old [${oldcols:-}] new [${cols:-}]"
    # Determine if we should print a new line - this shouldn't happen
    # often and these checks are faster than 'eval printf'
    if [[ -z "${oldcols:-}" || -z "${cols:-}" || -z "${line:-}" ||
      "${oldcols:-}" != "${cols:-}" ]] ; 
    then
      eval printf -v line '%.0s-' {1..$cols}
      debug 7 "Different terminal width - new horizontal rule"
    fi
  else
    if [[ -n "${line:-}" ]] ; then
      printf -v line '%.0s-' {1..80}
      debug 6 "Tput command not found - 80 col horizontal rule"
    fi
  fi

  declare -a data=()

  # Main loop to gather data
  for tmphost in "${hosts[@]}" ; do
    eval_host "${tmphost:-}"
  done

  # Output
  if [[ -z "${noclear:-}" ]] ; then
    clear
  fi
  echo -ne "Start time: $sdate\n"
  echo -ne "$host_print_ret"
  echo -n "End time: $($date) "

  # Write to a state change file
  if [[ -n "${changefile:-}" ]] ; then
    if [[ -n "${data[@]:-}" && -n "${olddata[@]:-}" && 
      "${data[@]:-}" != "${olddata[@]:-}" ]] ; then
      # Counter is odd numbered
      for (( count = 1 ; count < "${#data[@]}" ; count += 2 )) ; do
        if [[ "${data[$count]:-}" != "${olddata[$count]:-}" ]] ; then
          echo "[$($date)] [${data[$count -1]}] " \
            "${data[$count]:-}" >> "$changefile"
        fi
      done
    fi
    olddata="${data[@]:-}"
  fi

  # Limit runs
  if [[ -n "${runs:-}" ]] && (( runcount >= runs )) ; then
    break
  fi

  # Clean up
  unset host_print_ret
  sleep "$pause"
done

