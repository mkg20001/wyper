#!/bin/bash

check_task() {
  TASK="$STATE/$dev/task"
  if [ -e "$TASK" ]; then
    PID=$(cat "$TASK")
    if [ ! -e "/proc/$PID" ]; then
      if [ ! -z "$T_NOGRACE" ]; then
        log "ERROR: Task $PID crashed for device $dev"
      else
        log "Task $PID finished for device $dev at $(LC_ALL=C date)"
      fi
      rm -f "$TASK" "$TASK.progress"
    fi
  fi
}

scheudle_task() {
  T_NOGRACE=1 check_task

  if [ -e "$STATE/$dev/task" ]; then
    log "ERROR: Cannot execute task for $dev as one is already running"
  fi

  dev="$1"
  shift
  "$@" & pid=$!
  echo "$pid" > "$STATE/$dev/task"
}

dd_with_progress() {
  dd if=/dev/stdin "of=$DEV" & ddpid=$!
  while [ -e "/proc/$ddpid" ]; do
    CURPROG=$(progress -wp "$ddpid" -W 5 | head -n 2 | tail -n 1)
    echo "$CUR_LOG
$CURPROG" > "$STATE/$dev/task.progress"
  done
}

do_disk_wipe() {
  echo -e "Starting wipe...\n" > "$STATE/$DEV_NAME/task.progress"

  slog "Wiping $DEV with 000000 (1/3)..."
  cat /dev/zero | dd_with_progress
  slog "Wiping $DEV with 111111 (2/3)..."
  dd if=/dev/zero count=1024 bs=1024 | tr '\000' '\377' | dd_with_progress
  slog "Wiping $DEV with random (3/3)..."
  RAND=$(dd if=/dev/urandom bs=1024 count=1 | base64)
  yes "$RAND" | tr -d "\n" | dd_with_progress

  log "Creating msdos partition table on $DEV..."
  yes | parted "$DEV" mktable msdos

  log "Wiping completed for $DEV!"
  LC_ALL=C date > "$STATE/$DEV_NAME/wiped_at"
  dev="$DEV"
  check_task
}

do_act_wipe() {
  DEVID="$1"
  DEV_NAME="$2"
  dev="/dev/$DEV_NAME"
  DEV="$dev"

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

do_disk_all_wipe() {
  for DEV_STATE in "$STATE/"*; do
    DEVID=$(cat $DEV_STATE/id)
    DEV_NAME=$(basename $DEV_STATE)
    dev="/dev/$DEV_NAME"
    DEV="$dev"

    if [ ! -e "$DEV_STATE/task" ]; then
      scheudle_task "$DEV_NAME" do_disk_wipe
    fi
  done
}

do_act_wipe_confirmed() {
  if [ "$DEVID" == "." ]; then
    log "WIPING EVERYTHING"

    do_disk_all_wipe
  else
    dev="$DEV"
    scheudle_task "$DEV_NAME" do_disk_wipe
  fi
}

do_act_update() {
  echo "Updating..." > "$TMP/menu"
  yes yes | git pull
}
