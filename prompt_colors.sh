#!/bin/sh
RED='\e[0;31m' # 1
GREEN='\e[0;32m' # 2
YELLOW='\e[0;33m' # 3
BLUE='\e[0;34m' # 4
PURPLE='\e[0;35m' # 5
CYAN='\e[0;36m' # 6
BRRED='\e[1;31m' # 7
BRGREEN='\e[1;32m' # 8
BRYELLOW='\e[1;33m' # 9
BRBLUE='\e[1;34m' # 10
BRPURPLE='\e[1;35m' # 11
BRCYAN='\e[1;36m' # 12
NC='\e[0m' # 13

function plain() {
  echo $NC
}

# Genericize colors by groupings
function at_color() {
  local AT_COLOR=$NC
  if [[ $1 ]]; then
    AT_COLOR=$YELLOW
  fi
  echo $AT_COLOR
}

function user_color() {
  local USER_COLOR=$GREEN
  # superadmin -> red
  if [ "$1" = "root" -o "$1" = "admin" ]; then
    USER_COLOR=$RED
  fi
  # work -> blue
  if [ "$1" = "team" -o "$1" = "edison" ]; then
    USER_COLOR=$BLUE
  fi
  # me -> yellow
  if [ "$1" = "ivy" ]; then
    USER_COLOR=$BRYELLOW
  fi
  echo $USER_COLOR
}

function host_color() {
  local HOST_COLOR=$GREEN
  # superadmin/superadmin at work -> red
  if [ "$1" = "swervy" -o "$1" = "melchior" -o "$1" = "lenny" -o "$1" = "clyde" ]; then
    HOST_COLOR=$RED
  fi
  # personal -> purple
  if [ "$1" = "bertha" -o "$1" = "liona" -o "$1" = "mavie" ]; then
    HOST_COLOR=$PURPLE
  fi
  # edenlabs -> blue
  if [ "$1" = "minty" -o "$1" = "sherrie" ]; then
    HOST_COLOR=$BLUE
  fi
  # work -> green
  if [ "$1" = "gendo" -o "$1" = "ryoji" -o "$1" = "shinji" -o "$1" = "edison" ]; then
    HOST_COLOR=$GREEN
  fi
  echo $HOST_COLOR
}
