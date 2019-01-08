#!/bin/bash

do_toggle() {
  val=$(_db "$1")
  if [ "$val" == "T" ]; then
    _db "$1" F
  else
    _db "$1" T
  fi

  if [ ! -z "$2" ]; then
    $2 # return
  fi
}

get_toggle() {
  val=$(_db "$1")
  if [ "$val" == "T" ]; then
    return 0
  else
    return 1
  fi
}

get_toggle_display() {
  val=$(_db "$1")
  if [ "$val" == "T" ]; then
    echo "on"
  else
    echo "off"
  fi
}

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
  c_act h "disable health check alongside wipe: $(get_toggle_display disable_health_auto)" do_toggle disable_health_auto act_config
  c_act a "toggle automatic wiping: $(get_toggle_display auto_wipe)" do_toggle auto_wipe act_config
  c_act u "update" do_act_update
  c_act - "go back" act_main
  control_read
}

_act_list() {
  control_reset "$1"
  c_act . "$1 all" "do_act_$1" .

  for DEV_STATE in "$STATE"/*; do
    devid=$(cat "$DEV_STATE/id")
    devname=$(basename "$DEV_STATE")
    c_act "$devid" "$1 device $devid" "do_act_$1" "$devid" "$devname"
  done

  c_act - "go back" act_main
  control_read
}

act_wipe() {
  _act_list wipe
}

act_health() {
  _act_list check
}

act_jbod() {
  control_reset "JBOD configuration"
  c_act r "rescan and rebuild" do_jbod_rebuild
  c_act t "toggle automatic scan & rebuild: $(get_toggle_display jbod_automation)" do_toggle jbod_automation act_jbod
  c_act - "go back" act_main
  control_read
}

act_exit() {
  act_main
}

control_loop() {
  while true; do
    act_main
  done
}
