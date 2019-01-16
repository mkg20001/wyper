#!/bin/bash

render() {
  if ! get_toggle hide_banner; then
    banner
  else
    echo
  fi

  MIN=$(tput cols)

  if [ $MIN -gt 50 ]; then
    MIN=$(( $MIN - 4 ))
  fi

  render_diskstates

  if ! get_toggle hide_logs; then
    tail -n 10 "$LOG" | render_logs
  fi

  echo

  cat "$TMP/menu" | render_menu

  echo
}

render_logs() {
  while read line; do
    center "$line"
  done
}

render_diskstates() {
  if [ "$(ls -A $STATE)" ]; then
    center "Disks:"
    echo

    MIN=$(( $MIN - 4 ))

    for DEV_STATE in "$STATE"/*; do
      dev=$(basename "$DEV_STATE")
      center "$(cat $DEV_STATE/id): $(cat $DEV_STATE/display)"
      MIN=$(( $MIN - 16 ))
      if [ -e "$DEV_STATE/task.progress" ]; then
        cat "$DEV_STATE/task.progress" | render_logs
      else
        if [ -e "$DEV_STATE/wiped_at" ]; then
          center "Wiped at $(cat $DEV_STATE/wiped_at)"
        else
          center "Not wiped yet"
        fi

        if [ -e "$DEV_STATE/health_info" ]; then
          cat "$DEV_STATE/health_info" | render_logs
        else
          center "No health info"
        fi
      fi
      # center "Wiped at -"
      # center "Healthy"
      MIN=$(( $MIN + 16 ))
      echo
    done

    MIN=$(( $MIN + 4 ))
  else
    _MIN="$MIN"
    MIN=
    center "<No disks detected. Please attach some>"
    MIN="$_MIN"
  fi
}

render_menu() {
  args=()
  while read line; do
    args+=("$line")
  done

  _render_menu "${args[@]}"
}

_render_menu() {
  MIN=64

  center "$1"
  shift

  MIN=$(( $MIN - 4 ))
  while [ ! -z "$1" ]; do
    center "($1) $2"
    shift
    shift
  done
}

render_loop() {
  clear

  while true; do
    RENDERED=$(render)
    tput cup 0 0
    LSPACE=$(printf ' %.0s' $(seq 1 $(tput cols)))

    echo "$RENDERED" | sed "s|^|$LSPACE$(printf "\r")|g"

    sleep .1s
  done
}
