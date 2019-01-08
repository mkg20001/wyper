#!/bin/bash

control_read() {
  while read -sn1 char; do
    log "Char $char"
  done
}

control_main() {
  echo -e "Wyper v0.1.0\nc\nconfiguration\nw\nwipe and check health\nh\nhealth check\nj\nJBOD-configuration\ne\nexit" > "$TMP/menu"
}

control_loop() {
  control_main
}
