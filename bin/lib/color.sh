#!/usr/bin/env bash

echo_stderr() {
  echo -e "$*" 1>&2
}

echo_green() {
  echo_stderr "\033[0;32m$*\033[0m"
}
export -f echo_green

echo_red() {
  echo_stderr "\033[0;31m$*\033[0m"
}
export -f echo_red

echo_brightred() {
  echo_stderr "\033[0;91m$*\033[0m"
}
export -f echo_brightred

echo_yellow() {
  echo_stderr "\033[0;33m$*\033[0m"
}
export -f echo_yellow

echo_purple() {
  echo_stderr "\033[0;35m$*\033[0m"
}
export -f echo_purple

re_echo_purple() {
  tput cuu 1 && tput el
  echo_stderr "\r\033[0;35m$*\033[0m"
}
export -f re_echo_purple

echo_blue() {
  echo_stderr "\033[0;34m$*\033[0m"
}
export -f echo_blue

echo_bright_red() {
  echo_stderr -e "\e[101m$*\e[0;m"
}
