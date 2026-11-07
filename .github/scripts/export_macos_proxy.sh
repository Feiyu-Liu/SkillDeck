#!/usr/bin/env bash

set -euo pipefail

if [[ "$(uname -s)" != 'Darwin' ]]; then
  exit 0
fi

: "${GITHUB_ENV:?GITHUB_ENV must be configured by GitHub Actions}"

proxy_config="$(scutil --proxy)"

proxy_value() {
  local key="$1"
  awk -v key="$key" '$1 == key && $2 == ":" { print $3; exit }' \
    <<<"$proxy_config"
}

append_proxy() {
  local name="$1"
  local value="$2"
  printf '%s=%s\n' "$name" "$value" >>"$GITHUB_ENV"
}

https_enabled="$(proxy_value HTTPSEnable)"
https_host="$(proxy_value HTTPSProxy)"
https_port="$(proxy_value HTTPSPort)"
if [[ "$https_enabled" == '1' && -n "$https_host" && -n "$https_port" ]]; then
  https_proxy="http://$https_host:$https_port"
  append_proxy HTTPS_PROXY "$https_proxy"
  append_proxy https_proxy "$https_proxy"
  printf 'Configured the macOS HTTPS proxy for subsequent CI steps.\n'
fi

http_enabled="$(proxy_value HTTPEnable)"
http_host="$(proxy_value HTTPProxy)"
http_port="$(proxy_value HTTPPort)"
if [[ "$http_enabled" == '1' && -n "$http_host" && -n "$http_port" ]]; then
  http_proxy="http://$http_host:$http_port"
  append_proxy HTTP_PROXY "$http_proxy"
  append_proxy http_proxy "$http_proxy"
  printf 'Configured the macOS HTTP proxy for subsequent CI steps.\n'
fi

socks_enabled="$(proxy_value SOCKSEnable)"
socks_host="$(proxy_value SOCKSProxy)"
socks_port="$(proxy_value SOCKSPort)"
if [[ "$socks_enabled" == '1' && -n "$socks_host" && -n "$socks_port" ]]; then
  all_proxy="socks5h://$socks_host:$socks_port"
  append_proxy ALL_PROXY "$all_proxy"
  append_proxy all_proxy "$all_proxy"
  printf 'Configured the macOS SOCKS proxy for subsequent CI steps.\n'
fi

append_proxy NO_PROXY '127.0.0.1,localhost,::1'
append_proxy no_proxy '127.0.0.1,localhost,::1'
