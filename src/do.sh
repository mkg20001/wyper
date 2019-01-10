#!/bin/bash

T_NOGRACE=false

check_task() {
  TASK="$STATE/$dev/task"
  if [ -e "$TASK" ]; then
    PID=$(cat "$TASK")
    if [ ! -e "/proc/$PID" ]; then
      if $T_NOGRACE; then
        log "ERROR: Task $PID crashed for device $dev"
      else
        log "Task $PID finished for device $dev at $(LC_ALL=C date)"
      fi
      rm -f "$TASK" "$TASK.progress"
    fi
  fi
}

scheudle_task() {
  T_NOGRACE=true check_task

  if [ -e "$STATE/$dev/task" ]; then
    log "ERROR: Cannot execute task for $dev as one is already running"
  fi

  dev="$1"
  shift
  "$@" & pid=$!
  echo "$dev/$pid" > "$STATE/$dev/task"
}

dd_with_progress() {
  dd if=/dev/stdin "of=$DEV" & ddpid=$!
  while [ -e "/proc/$ddpid" ]; do
    CURPROG=$(progress -wp "$ddpid" | head -n 2 | tail -n 1)
    echo "$CURPROG
$CUR_LOG" > "$STATE/$dev/task.progress"
  done
}

do_disk_wipe() {
  DEV="$1"
  DEV_NAME="$2"

  echo "Starting wipe..." > "$STATE/$DEV_NAME/task.progress"

  slog "Wiping $DEV with 000000 (1/3)..."
  cat /dev/zero | dd_with_progress
  slog "Wiping $DEV with 111111 (2/3)..."
  dd if=/dev/zero count=1024 bs=1024 | tr '\000' '\377' | dd_with_progress
  slog "Wiping $DEV with random (3/3)..."
  # RAND=$(dd if=/dev/urandom bs=$(( 1024 * 1024 )) count=1 | base64 -d)
  # yes "" | tr -d "\n" | dd_with_progress

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
  dev="$DEV"
  scheudle_task "$DEV_NAME" do_disk_wipe "$DEV" "$DEV_NAME"
}

do_act_update() {
  echo "Updating..." > "$TMP/menu"
  yes yes | git pull
}
