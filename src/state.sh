#!/bin/bash

sync_state() {
  UUIDS=()

  for DEV_STATE in "$STATE/"*; do
    UUID=$(cat "$DEV_STATE/uuid")
    UUIDS+=("$UUID")

    if [ ! -d "$PSTATE/$UUID" ]; then
      mkdir -p "$PSTATE/$UUID"
    fi

    for tag in wiped_at health_info; do
      PSTATE_TAG="$PSTATE/$UUID/$tag"
      DEV_STATE_TAG="$DEV_STATE/$tag"

      if [ -e "$PSTATE_TAG" ] && [ ! -e "$DEV_STATE_TAG" ]; then
        cp "$PSTATE_TAG" "$DEV_STATE_TAG"
      elif [ ! -e "$PSTATE_TAG" ] && [ -e "$DEV_STATE_TAG" ]; then
        cp "$DEV_STATE_TAG" "$PSTATE_TAG"
      fi
    done
  done

  for i in "$PSTATE"/*; do
    UUID=$(basename "$i")
    if ! contains "$UUID" "${UUIDS[@]}"; then
      rm -rf "$i"
    fi
  done
}
