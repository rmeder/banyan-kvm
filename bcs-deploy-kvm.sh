#!/bin/bash

# This script automates the deployment of a Red Hat Enterprise Linux 9 VM using specific UEFI firmware settings
# and hypervisor chipset configurations. It handles all aspects from checking prerequisites, downloading necessary
# files, setting up the firmware, to creating the virtual machine using `virt-install`.
#
# Configuration:
#   - The script requires a JSON configuration file to read the VM settings which includes memory, CPUs, disk path,
#     firmware paths, and whether to perform package checks.
#   - The JSON configuration should be specified at `CONFIG_FILE` with the proper path.
#
# Functions:
#   ensure_packages_installed() - Checks and installs required packages like jq, virt-manager, libvirt.
#   install_firmware_config() - Checks if custom UEFI firmware configuration exists, installs if absent, and reloads libvirtd.
#
# Usage:
#   - Edit the CONFIG_FILE path in the script to point to your JSON configuration file.
#   - Ensure the script is executable: chmod +x <script_name.sh>
#   - Run the script: ./<script_name.sh>

# Function to ensure required packages are installed
ensure_packages_installed() {
    local packages=("jq" "virt-manager" "libvirt-daemon-system" "libvirt-clients")
    local missing_packages=()

    for pkg in "${packages[@]}"; do
        if ! dpkg -s $pkg >/dev/null 2>&1; then
            missing_packages+=($pkg)
        fi
    done

    if [ ${#missing_packages[@]} -gt 0 ]; then
        echo "Missing required packages: ${missing_packages[@]}"
        echo "Attempting to install missing packages..."
        sudo apt-get update
        sudo apt-get install -y ${missing_packages[@]}
    fi
}

# Function to install custom firmware configuration and reload libvirtd
install_firmware_config() {
    local firmware_config_path="/etc/qemu/firmware/"
    local firmware_config_file="${firmware_config_path}10-sonicwall-x86_64-dev-enrolled.json"

    # Create directory if it doesn't exist
    sudo mkdir -p $firmware_config_path

    # Check if the firmware config file exists, install if not
    if [ ! -f $firmware_config_file ]; then
        echo "Installing custom firmware configuration..."
        cat > $firmware_config_file << EOF
{
    "description": "UEFI firmware for x86_64, with Secure Boot, SB enabled, SonicWall certs enrolled",
    "interface-types": [
        "uefi"
    ],
    "mapping": {
        "device": "flash",
        "executable": {
            "filename": "/usr/share/OVMF/OVMF_CODE.sw.dev.fd",
            "format": "raw"
        },
        "nvram-template": {
            "filename": "/usr/share/OVMF/OVMF_VARS.sw.dev.fd",
            "format": "raw"
        }
    },
    "targets": [
        {
            "architecture": "x86_64",
            "machines": [
                "pc-q35-*"
            ]
        }
    ],
    "features": [
        "verbose-dynamic"
    ],
    "tags": []
}
EOF
        echo "Custom firmware configuration installed."
        # Reload libvirtd to apply changes
        sudo systemctl reload libvirtd
        echo "libvirtd reloaded."
    else
        echo "Custom firmware configuration already installed."
    fi
}

# Function to download files if they do not exist
download_if_missing() {
    local url=$1
    local path=$2

    if [ ! -f $path ]; then
        echo "Downloading $path..."
        curl -o $path $url
        if [ $? -ne 0 ]; then
            echo "Failed to download $path from $url"
            exit 1
        fi
    fi
}

# Load configuration from JSON file
CONFIG_FILE="bsc-kvm-config.json"

# Read config settings
VM_NAME=$(jq -r '.vm_name' $CONFIG_FILE)
MEMORY=$(jq -r '.memory' $CONFIG_FILE)
CPUS=$(jq -r '.cpus' $CONFIG_FILE)
DISK_PATH=$(jq -r '.disk_path' $CONFIG_FILE)
OS_VARIANT=$(jq -r '.os_variant' $CONFIG_FILE)
FIRMWARE_DIR=$(jq -r '.firmware_dir' $CONFIG_FILE)
OVMF_BASE_URL=$(jq -r '.ovmf_base_url' $CONFIG_FILE)
OVMF_CODE=$(jq -r '.ovmf_code' $CONFIG_FILE)
OVMF_CODE=$(jq -r '.ovmf_vars' $CONFIG_FILE)
CHECK_PACKAGES=$(jq -r '.check_packages' $CONFIG_FILE)
QCOW2_IMAGE_URL=$(jq -r '.qcow2_image_url' $CONFIG_FILE)
QCOW2_IMAGE_PATH=$(jq -r '.qcow2_image_path' $CONFIG_FILE)


# Conditionally check and install required packages
if [[ "$CHECK_PACKAGES" == "true" ]]; then
    ensure_packages_installed
fi

# Install custom firmware configuration and reload libvirtd
install_firmware_config

# Setup directories and source files
# Create directories if they don't exist
mkdir -p $FIRMWARE_DIR
mkdir -p $(dirname $QCOW_IMAGE_PATH)

# Download firmware files
download_if_missing "$OVMF_BASE_URL$OVMF_CODE" "$FIRMWARE_DIR$OVMF_CODE"
download_if_missing "$OVMF_BASE_URL$OVMF_VARS" "$FIRMWARE_DIR$OVMF_VARS"
download_if_missing "$BCS_IMAGE_URL" "$BCS_IMAGE_PATH"

# Set permissions
chmod 644 $FIRMWARE_DIR$OVMF_CODE
chmod 644 $FIRMWARE_DIR$OVMF_VARS
chmod 644 $BCS_IMAGE_PATH

# Verify everything is in place
echo "All required files have been downloaded and placed correctly with proper permissions."

# Create the VM with specific hypervisor chipset, firmware, watchdog, and OS variant
virt-install \
    --name $VM_NAME \
    --memory $MEMORY \
    --vcpus $CPUS \
    --os-variant $OS_VARIANT \
    --import \
    --disk $DISK_PATH,bus=virtio \
    --graphics spice \
    --video qxl \
    --boot uefi,loader="${FIRMWARE_DIR}${OVMF_CODE}",nvram_template="${FIRMWARE_DIR}${OVMF_VARS}" \
    --machine q35 \
    --console pty,target_type=serial \
    --watchdog i6300esb,action=reset \
    --print-xml > $VM_NAME.xml

# Option to edit XML for custom configurations
echo "XML configuration file created: $VM_NAME.xml"
echo "Edit this file if customization is needed, then run:"
echo "virsh define $VM_NAME.xml"

echo "VM $VM_NAME is configured. Use 'virsh start $VM_NAME' to run the VM after customization."
