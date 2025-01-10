#!/usr/bin/env bash
set -eu

declare -A boards=(
  ["klipper-skr-mini-v2.config"]="stm32f103xe_36FFD6054246303633571157-if00"
  ["klipper-sht36.config"]="stm32f072xb_450049001057425835303220-if00"
  ["klipper-v0display.config"]="stm32f042x6_23000C001843304754393320-if00"
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

function update_config() {
  python_code="
import kconfiglib
import sys
a = kconfiglib.Kconfig(filename=sys.argv[1])
a.load_config(filename=sys.argv[2],replace=False)
a.write_config(filename=sys.argv[2],save_old=True)
"
  pushd "$klipper_path"
  PYTHONPATH=lib/kconfiglib python3 -c "$python_code" src/Kconfig $1
  popd
}

configs_dir="$(realpath $(dirname "$0"))"
sudo systemctl stop klipper

for config_name in "${!boards[@]}"; do
  serial_path="/dev/serial/by-id/usb-Klipper_${boards[$config_name]}"
  serial_katapult_path="/dev/serial/by-id/usb-katapult_${boards[$config_name]}"
  config_path="$configs_dir/$config_name"
  echo "Update board config: $config_path"
  update_config "$config_path"
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
sudo systemctl start klipper
