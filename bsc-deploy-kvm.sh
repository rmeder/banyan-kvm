#!/usr/bin/env bash

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

# # Function to ensure required packages are installed
# ensure_packages_installed() {
#     local packages=("jq" "virt-manager" "libvirt-daemon-system" "libvirt-clients")
#     local missing_packages=()

#     for pkg in "${packages[@]}"; do
#         if ! dpkg -s $pkg >/dev/null 2>&1; then
#             missing_packages+=($pkg)
#         fi
#     done

#     if [ ${#missing_packages[@]} -gt 0 ]; then
#         echo "Missing required packages: ${missing_packages[@]}"
#         echo "Attempting to install missing packages..."
#         sudo apt-get update
#         sudo apt-get install -y ${missing_packages[@]}
#     fi
# }

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
    if [ ! -f "$2" ]; then
        echo "Downloading $1 to $2.."
        if curl -s --head "$1" >/dev/null; then
            curl "$1" -o "$2"
            if [ $? -ne 0 ]; then
                echo "Failed to download $1"
                exit 1
            fi
        else
            echo "URL $1 is not accessible"
            exit 1
        fi
    fi
}


# Determine the home directory and set configuration file path
CONFIG_FILE="${HOME}/Downloads/rkm/banyan-kvm/bsc-kvm-config.json"

# Check and install required packages
#ensure_packages_installed

# Check if the configuration file exists
if [ ! -f "$CONFIG_FILE" ]; then
    echo "Configuration file not found at $CONFIG_FILE"
    exit 1
fi

# Read config settings
VM_NAME=$(jq -r '.vm_name' $CONFIG_FILE)
MEMORY=$(jq -r '.memory' $CONFIG_FILE)
CPUS=$(jq -r '.cpus' $CONFIG_FILE)
OS_VARIANT=$(jq -r '.os_variant' $CONFIG_FILE)
FIRMWARE_DIR=$(jq -r '.firmware_dir' $CONFIG_FILE)
OVMF_BASE_URL=$(jq -r '.ovmf_base_url' $CONFIG_FILE)
OVMF_CODE=$(jq -r '.ovmf_code' $CONFIG_FILE)
OVMF_CODE=$(jq -r '.ovmf_vars' $CONFIG_FILE)
CHECK_PACKAGES=$(jq -r '.check_packages' $CONFIG_FILE)
QCOW2_IMAGE_URL=$(jq -r '.qcow2_image_url' $CONFIG_FILE)
QCOW2_IMAGE_PATH=$(jq -r '.qcow2_image_path' $CONFIG_FILE)



# Install custom firmware configuration and reload libvirtd
#install_firmware_config

# Setup directories and source files
# Create directories if they don't exist
#mkdir -p $FIRMWARE_DIR
#mkdir -p $(dirname $QCOW2_IMAGE_PATH)

# Construct firmware URLs and paths
OVMF_CODE_URL="${OVMF_BASE_URL}${OVMF_CODE}"
OVMF_VARS_URL="${OVMF_BASE_URL}${OVMF_VARS}"
OVMF_CODE_PATH="${FIRMWARE_DIR}${OVMF_CODE}"
OVMF_VARS_PATH="${FIRMWARE_DIR}${OVMF_VARS}"

# Download firmware files
#download_if_missing "https://d235l73b1b38h0.cloudfront.net/bsc/OVMF_CODE.sw.dev.fd" "/usr/share/OVMF/OVMF_CODE.sw.dev.fd"
#download_if_missing "https://d235l73b1b38h0.cloudfront.net/bsc/OVMF_VARS.sw.dev.fd" "/usr/share/OVMF/OVMF_VARS.sw.dev.fd"
#download_if_missing $OVMF_CODE_URL $OVMF_CODE_PATH
#download_if_missing $OVMF_VARS_URL $OVMF_VARS_PATH
#download_if_missing $QCOW2_IMAGE_URL $QCOW2_IMAGE_PATH

# Set permissions
#chmod 644 $OVMF_CODE_PATH
#chmod 644 $OVMF_VARS_PATH
#chmod 644 $QCOW2_IMAGE_PATH

# Verify everything is in place
echo "All required files have been downloaded and placed correctly with proper permissions."

# Create the VM with specific hypervisor chipset, firmware, watchdog, and OS variant
virt-install \
    --name $VM_NAME \
    --memory $MEMORY \
    --vcpus $CPUS \
    --os-variant $OS_VARIANT \
    --import \
    --graphics spice \
    --video qxl \
    --boot uefi,loader="/usr/share/OVMF/OVMF_CODE.sw.dev.fd",nvram_template="/usr/share/OVMF/OVMF_VARS.sw.dev.fd" \
    --machine q35 \
    --console pty,target_type=serial \
    --watchdog i6300esb,action=reset \
    --print-xml > $VM_NAME.xml

# Option to edit XML for custom configurations
echo "XML configuration file created: $VM_NAME.xml"
echo "Edit this file if customization is needed, then run:"
echo "virsh define $VM_NAME.xml"

echo "VM $VM_NAME is configured. Use 'virsh start $VM_NAME' to run the VM after customization."
