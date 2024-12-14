#!/usr/bin/env bash
set -eu

declare -A boards=(
  ["klipper-skr-mini-v2.config"]="stm32f103xe_36FFD6054246303633571157-if00"
  ["klipper-sht36.config"]="stm32f072xb_450049001057425835303220-if00"
)

klipper_path="$HOME/klipper"
make_flags=("-j4")

function build_klipper() {
  pushd "$klipper_path"
  cp --force --no-target-directory "$1" .config
  make "${make_flags[@]}"
  popd
}

function enter_bootloader() {
    PYTHONPATH="$klipper_path/scripts" python3 -c "import flash_usb as u; u.enter_bootloader('$1')"
}

function flash_board() {
  # Enter bootloader
  # Flash
  make --directory "$klipper_path" flash FLASH_DEVICE="$1"
}

for config_name in "${!boards[@]}"; do
  serial_path="/dev/serial/by-id/usb-Klipper_${boards[$config_name]}"
  serial_katapult_path="/dev/serial/by-id/usb-katapult_${boards[$config_name]}"
  config_path="$(dirname "$0")/$config_name"
  if ! [[ ( -e "$serial_path" || -e "$serial_katapult_path") &&  -e "$config_path" ]]; then
    echo "Serial path or config path were not found! Skipping ${config_name}..."
    continue
  fi
  echo "Build Klipper"
  build_klipper "$config_path"

  if [ -e "$serial_katapult_path" ]; then
    echo "Already in bootloader"
  elif [ -e "$serial_path" ]; then
    echo "Entering bootloader"
    enter_bootloader "$serial_path"
    sleep 1
  else
    echo "Serial path for board ${config_name} was not found! Skipping..."
    continue
  fi
    
  echo "Flash Klipper"
  flash_board "$serial_katapult_path"
  echo "Updated $serial_path with config $config_path!"
done