#!/usr/bin/env bash
set -euo pipefail

EXAMPLE_FILE=${1:-.env.example}
ENV_FILE=${2:-.env}

# ensure target file exists
[[ -f "$ENV_FILE" ]] || touch "$ENV_FILE"

declare -A example_values
while IFS= read -r line || [[ -n $line ]]; do
  [[ $line =~ ^[[:space:]]*$ ]] && continue
  [[ $line =~ ^[[:space:]]*# ]] && continue
  IFS='=' read -r key value <<< "$line"
  example_values["$key"]="$value"
done < "$EXAMPLE_FILE"

declare -A existing
while IFS= read -r line || [[ -n $line ]]; do
  [[ $line =~ ^[[:space:]]*$ ]] && continue
  [[ $line =~ ^[[:space:]]*# ]] && continue
  IFS='=' read -r key value <<< "$line"
  existing["$key"]=1
done < "$ENV_FILE"

for key in "${!example_values[@]}"; do
  if [[ -z ${existing[$key]+x} ]]; then
    printf '%s=%s\n' "$key" "${example_values[$key]}" >> "$ENV_FILE"
    echo "Added $key from $EXAMPLE_FILE to $ENV_FILE"
  fi
done

temp_file=$(mktemp)
trap 'rm -f "$temp_file"' EXIT

while IFS= read -r line || [[ -n $line ]]; do
  if [[ $line =~ ^[[:space:]]*$ ]]; then
    printf '\n' >> "$temp_file"
    continue
  fi
  if [[ $line =~ ^[[:space:]]*# ]]; then
    printf '%s\n' "$line" >> "$temp_file"
    continue
  fi
  IFS='=' read -r key rest <<< "$line"
  if [[ -n ${example_values[$key]+x} ]]; then
    printf '%s\n' "$line" >> "$temp_file"
  else
    echo "Removed $key from $ENV_FILE"
  fi
done < "$ENV_FILE"

mv "$temp_file" "$ENV_FILE"
trap - EXIT
