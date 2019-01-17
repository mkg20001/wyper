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
  dd if=/dev/stdin "of=$DEV" o=noerror iflag=fullblock oflag=direct bs=16M & ddpid=$!
  while [ -e "/proc/$ddpid" ]; do
    CURPROG=$(progress -wp "$ddpid" -W 5 | head -n 2 | tail -n 1)
    echo "$CUR_LOG
$CURPROG" > "$STATE/$dev/task.progress"
  done
}

ch_badblocks() {
  BAFILE="$TMP/$DEV_NAME.badblocks"
  BALOG="$BAFILE.log"
  touch "$BALOG"
  LC_ALL=C badblocks -w -s -t random -v -o "$BAFILE" "$DEV" >>"$BALOG" 2>>"$BALOG" & bbpid=$!
  while [ -e "/proc/$bbpid" ]; do
    CURSTATE=$(echo $(tail -n 1 "$BALOG" | sed "s|: .*||g"))
    CURPROG=$(cat "$BALOG" | fold -w 41 | tail -n 2 | head -n 1 | sed "s|[^0-9a-z/,:% .]||g" | sed "s|^ *||g" | sed "s| *$||g")
    echo "$CUR_LOG ($CURSTATE)
$CURPROG" > "$STATE/$dev/task.progress"

    sleep 1s
  done

  BA_FINAL=$(tail -n 1 "$BALOG.log")
  if [ ! -s "$TMP/$DEV.badblocks" ]; then
    BA_FINAL="Healthy: $BA_FINAL"
  else
    BA_FINAL="**UNHEALTHY**: $BA_FINAL"
  fi
  log "$BA_FINAL"
  cat "$BAFILE"

  echo "$BA_FINAL" > "$STATE/$DEV_NAME/health_info"
}

do_disk_wipe() {
  echo -e "Starting wipe...\n" > "$STATE/$DEV_NAME/task.progress"

  slog "Checking bad blocks on $DEV (1/4)..."
  ch_badblocks

  slog "Wiping $DEV with 000000 (2/4)..."
  cat /dev/zero | dd_with_progress
  slog "Wiping $DEV with 111111 (3/4)..."
  dd if=/dev/zero count=1024 bs=1024 | tr '\000' '\377' | dd_with_progress
  slog "Wiping $DEV with random (4/4)..."
  RAND=$(dd if=/dev/urandom bs=1024 count=1 2>/dev/null | base64)
  yes "$RAND" | tr -d "\n" | dd_with_progress

  log "Creating msdos partition table on $DEV..."
  yes | parted "$DEV" mktable msdos > /dev/null

  log "Wiping completed for $DEV!"
  LC_ALL=C date > "$STATE/$DEV_NAME/wiped_at"

  echo "Wiped '$(cat "$STATE/$DEV_NAME/display")' at $(LC_ALL=C date)" >> "$ALOG"
  echo "Healthcheck result was: $BA_FINAL" >> "$ALOG"
  cat "$BAFILE" | sed "s|^|[BADBLOCK] |g" >> "$ALOG"
  rm "$BAFILE"*

  dev="$DEV"
  sync_state
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

    if [ ! -e "$DEV_STATE/task" ] && [ ! -e "$DEV_STATE/wiped_at" ]; then
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
