#!/usr/bin/env bash

declare network="${1:-"Wi-Fi"}"

declare -a bypassdomains=(
 '*.local'
  '169.254/16'
  '*.slack-edge.com'
  '*.slack.com'
  '*.googleapis.com'
  '*.mail.google.com'
  '*.ssl.gstatic.com'
)

bypass () {
  declare hoststr="$(printf "'%s' " "${bypassdomains[@]}")"
  networksetup -setproxybypassdomains "${network}" "${hoststr}"
}

setproxy () {
  networksetup -setwebproxy "${network}" 127.0.0.1 8080
  networksetup -setsecurewebproxy "${network}" 127.0.0.1 8080
}

toggle () {
  declare state="$1"
  if [[ "$state" == "Yes" ]]; then
    networksetup -setsecurewebproxystate "${network}" off
    networksetup -setwebproxystate "${network}" off
    echo "OFF"
  else
    bypass
    setproxy
    networksetup -setsecurewebproxystate "${network}" on
    networksetup -setwebproxystate "${network}" on
    echo "ON"
  fi
}

declare unsecstate="$(networksetup -getwebproxy "$network" | grep -E '^Enabled: (No|Yes)$' | cut -d' ' -f2)"
declare secstate="$(networksetup -getsecurewebproxy "$network" | grep -E '^Enabled: (No|Yes)$' | cut -d' ' -f2)"

if [[ "${secstate}" != "${unsecstate}" ]]; then
  networksetup -setsecurewebproxystate "${network}" off
  networksetup -setwebproxystate "${network}" off
fi

toggle "${secstate}"

