#!/bin/bash

control_read() {
  echo "$newmenu" > "$TMP/menu"
  while true; do
    read -sn1 char

    if [ ! -z "${act["$char"]}" ]; then
     ${act["$char"]}
     return 0
    fi
  done
}

declare -A act

control_reset() {
  act=()
  newmenu="$1"
}

c_act() {
  key="$1"
  shift
  desc="$1"
  shift
  act["$key"]="$*"
  newmenu="$newmenu
$key
$desc"
}

act_main() {
  control_reset "Wyper v0.1.0"
  c_act c "configuration" act_config
  c_act w "wipe and check health" act_wipe
  c_act h "health check" act_health
  c_act j "JBOD configuration" act_jbod
  c_act e "exit" act_exit
  control_read
}

act_config() {
  control_reset "Configuration"
  c_act k "keyboard layout" act_keyboard
  c_act h "do health check alongside wipe: <true/false>"
  c_act a "toggle automatic wiping: <on/off>"
  c_act "-" "go back" act_main
  control_read
}

act_wipe() {
  control_reset "Wipe"
  c_act "." "wipe all" do_act_wipe .

  for DEV_STATE in "$STATE"/*; do
    devid=$(cat "$DEV_STATE/id")
    devname=$(basename "$DEV_STATE")
    c_act "$devid" "wipe device $devid" do_act_wipe "$devname"
  done

  c_act "-" "go back" act_main
  control_read
}

control_loop() {
  while true; do
    act_main
  done
}
