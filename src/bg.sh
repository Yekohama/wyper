#!/bin/bash

detect_root_location() {
  ROOT_MNT=$(awk -v needle="/" '$2==needle {print $1}' /proc/mounts)
  ROOT_DEV_NAME=$(lsblk -no pkname "$ROOT_MNT")
  ROOT_DEV="/dev/$ROOT_DEV_NAME"

  log "System is mounted at $ROOT_MNT which is part of $ROOT_DEV, ignoring that disk"
}

get_from_list() {
  head -n "$1" | tail -n 1
}

detect_disks() {
  # log "Detecting disks..."

  DEVS_J=$(lsblk -Jo name,rm,size,ro,type,mountpoint,hotplug,label,uuid,model,serial,rev,vendor,hctl | jq '.blockdevices[] | select(.type == "disk" and .name != "'"$ROOT_DEV_NAME"'")')
  DEVS=$(echo "$DEVS_J" | jq -r ".name")
  # log "Found disk(s): $(echo $DEVS)"
  DEVS_ARRAY=($DEVS)

  for dev in $DEVS; do
    DEV_STATE="$STATE/$dev"
    DEV_J=$(echo "$DEVS_J" | jq -sr '.[] | select(.name == "'"$dev"'")')
    if [ -e "$DEV_STATE" ] && [ "$(gen_dev_uuid)" != "$(cat $DEV_STATE/uuid)" ]; then
      rm_routine
    fi
    if [ ! -e "$DEV_STATE" ]; then
      add_routine
    fi
  done

  for DEV_STATE in "$STATE"/*; do
    dev=$(basename "$DEV_STATE")
    if ! contains "$dev" "${DEVS_ARRAY[@]}"; then
      rm_routine
    fi
  done
  # DEV_NAME_LIST=$(echo "$DEVS_J" | jq -sr '.[] | .vendor + " " + .model + " " + .serial + " (" + .size + ")"')
}

gen_dev_uuid() {
  echo "$DEV_J" | jq -c '[.vendor, .model, .serial, .rev, .size, .hctl]' | sha256sum | fold -w 64 | head -n 1
}

add_routine() {
  log "Generating metadata for new device $dev..."

  mkdir -p "$DEV_STATE"
  echo "$DEV_J" | jq -r '.vendor + " " + .model + " " + .serial + " rev " + .rev + " (" + .size + ")"' | sed -r "s|  +| |g" | sed -r "s|^ *||g" > "$DEV_STATE/display"
  gen_dev_uuid > "$DEV_STATE/uuid"
  get_free_id > "$DEV_STATE/id"

  log "Added as $(cat $DEV_STATE/id)!"
}

rm_routine() {
  log "Removing metadata for obsolete device $dev..."
  kill -s SIGKILL "$(cat $DEV_STATE/task 2> /dev/null || /bin/true)" 2> /dev/null || /bin/true # kill obsolete task
  rm -rf "$DEV_STATE"
  log "Removed"
}

get_free_id() {
  ids=$(cat "$STATE"/*/id)
  for freeid in "${ID_ARRAY[@]}"; do
    if ! contains "$freeid" $ids; then
      echo "$freeid"
      return 0
    fi
  done

  log "ERROR: We're out of ids! You really managed to get ${#ID_LIST} drives plugged into this thing?! Report that as an issue!"
}

bg_loop() {
  while true; do
    detect_disks
    sleep 1s
  done
}