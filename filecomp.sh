#!/usr/bin/env bash

declare -A filedb
for file in $@; do
  if [[ -f "$file" ]]; then
#    read checksum name \
#      < <(md5sum "$file")
#    filedb["$file"]="$checksum"
    read serial \
      < <(openssl x509 -in "$file" -noout -serial \
        | cut -d'=' -f2)
    filedb["$file"]="$serial"
  fi
done

declare -a processed
for outer in "${!filedb[@]}"; do
  for inner in "${!filedb[@]}"; do
    [[ " ${processed[*]} " =~ " ${inner} " ]] && continue
    if [[ "$inner" != "$outer" ]]; then
      if [[ "${filedb[${inner}]}" == "${filedb[${outer}]}" ]]; then
        echo "${outer} => ${inner}"
      fi
    fi
  done
  processed+=("$outer")
done
