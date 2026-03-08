#!/bin/bash
plain() {
  echo "$NC"
}

# Genericize colors by groupings
at_color() {
  local AT_COLOR=$NC
  if [[ $1 ]]; then
    AT_COLOR=$YELLOW
  fi
  echo "$AT_COLOR"
}

user_color() {
  local USER_COLOR=$GREEN
  # superadmin -> red
  if [ "$1" = "root" ] || [ "$1" = "admin" ]; then
    USER_COLOR=$RED
  fi
  # work -> blue
  if [ "$1" = "team" ] || [ "$1" = "edison" ]; then
    USER_COLOR=$BLUE
  fi
  # me -> yellow
  if [ "$1" = "ivy" ]; then
    USER_COLOR=$BRYELLOW
  fi
  echo "$USER_COLOR"
}

host_color() {
  local HOST_COLOR=$GREEN
  # superadmin/superadmin at work -> red
  if [ "$1" = "swervy" ] || [ "$1" = "melchior" ] || [ "$1" = "lenny" ] || [ "$1" = "clyde" ]; then
    HOST_COLOR=$RED
  fi
  # personal -> purple
  if [ "$1" = "bertha" ] || [ "$1" = "liona" ] || [ "$1" = "mavie" ]; then
    HOST_COLOR=$PURPLE
  fi
  # edenlabs -> blue
  if [ "$1" = "minty" ] || [ "$1" = "sherrie" ]; then
    HOST_COLOR=$BLUE
  fi
  # work -> green
  if [ "$1" = "gendo" ] || [ "$1" = "ryoji" ] || [ "$1" = "shinji" ] || [ "$1" = "edison" ]; then
    HOST_COLOR=$GREEN
  fi
  echo "$HOST_COLOR"
}
