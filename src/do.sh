#!/bin/bash

scheudle_task() {
  if [ -e "$STATE/$dev/task" ]; then
    log "ERROR: Cannot execute task for $dev as one is already running"
  fi

  dev="$1"
  shift
  "$@" & pid=$!
  echo "$dev/$pid" > "$STATE/$dev/task"
}

do_disk_wipe() {
  DEV="$1"
  DEV_NAME="$2"

  log "Wiping $DEV with 000000 (1/3)..."
  dd if=/dev/null "of=$DEV"
  log "Wiping $DEV with 111111 (2/3)..."
  dd if=/dev/null "of=$DEV" # TODO: use 0xffff
  log "Wiping $DEV with random (3/3)..."
  dd if=/dev/null "of=$DEV" # TODO: use random (but make it fast)

  log "Creating msdos partition table on $DEV..."
  yes | parted "$DEV" mktable msdos

  log "Wiping completed for $DEV!"
}

do_act_wipe() {
  DEVID="$1"
  DEV_NAME="$2"

  if [ "$DEVID" == "." ]; then
    control_reset "wipe everything"
  else
    control_reset "wipe $(cat $STATE/$DEV_NAME/display)"
  fi

  c_act y "Yes" do_act_wipe_confirmed
  c_act n "No" act_wipe
  control_read
}

test_task() {
  log "Task test"
}

do_act_wipe_confirmed() {
  scheudle_task "$DEV_NAME" test_task
}

do_act_update() {
  echo "Updating..." > "$TMP/menu"
  yes yes | git pull
}
