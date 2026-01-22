#!/bin/bash

# MIT License
# Copyright (c) 2026 And-rix
# GitHub: https://github.com/And-rix
# License: /LICENSE

export LANG=en_US.UTF-8

# Import misc functions
source <(curl -fsSL https://raw.githubusercontent.com/netzspezialist/pve-scripts/main/misc/misc.sh)
source <(curl -fsSL https://raw.githubusercontent.com/netzspezialist/pve-scripts/main/vdsm/vdsm-functions.sh)

# Header
create_header "vDSM-Arc-Install"
sleep 1

# User confirmation
ask_user_confirmation

# Info message
whiptail --title "vDSM-Arc default settings" --msgbox \
"CPU: 2x | Mem: 4096MB | NIC: vmbr0 | Storage: selectable

---

Can be changed after creation!" 12 60

# Storage selection
pve_storages

# Ensure unzip + wget are available
unzip_check_install

# Paths
ISO_STORAGE_PATH="/var/lib/vz/template/iso"
DOWNLOAD_PATH="/var/lib/vz/template/tmp"
mkdir -p "$DOWNLOAD_PATH"

# Download release from GitHub
arc_release_choice
arc_release_download

# Extract .img
unzip_img

# Get version
VERSION=$(echo "$LATEST_FILENAME" | grep -oP "\d+\.\d+\.\d+(-[a-zA-Z0-9]+)?")

# Rename extracted image
if [ -f "$ISO_STORAGE_PATH/arc.img" ]; then
    NEW_IMG_FILE="$ISO_STORAGE_PATH/arc-${VERSION}.img"
    mv "$ISO_STORAGE_PATH/arc.img" "$NEW_IMG_FILE"
else
    echo -e "${R}Error: No extracted arc.img found!${X}"
    exit 1
fi

# Define VM parameters
arc_default_vm

## Optional: let user choose a custom VM ID
while true; do
    CUSTOM_VM_ID=$(whiptail --title "Custom VM ID (optional)" \
        --inputbox "Enter a numeric VM ID to use, or leave blank to keep $VM_ID:" 10 70 3>&1 1>&2 2>&3)

    # If cancelled, exit gracefully
    if [[ $? -ne 0 ]]; then
        whiptail --title "Cancelled" --msgbox "Installation cancelled." 8 50
        exit 1
    fi

    # Blank input -> keep current VM_ID (auto-selected)
    if [[ -z "$CUSTOM_VM_ID" ]]; then
        break
    fi

    # Validate numeric
    if ! [[ "$CUSTOM_VM_ID" =~ ^[0-9]+$ ]]; then
        whiptail --title "Invalid ID" --msgbox "VM ID must be a positive number." 8 60
        continue
    fi

    # Check not already in use
    if vm_check_exist "$CUSTOM_VM_ID"; then
        whiptail --title "ID In Use" --msgbox "VM ID $CUSTOM_VM_ID already exists. Please choose another." 8 60
        continue
    fi

    # Accept
    VM_ID="$CUSTOM_VM_ID"
    break
done

# Spinner group
{
    # Create VM
    qm create "$VM_ID" \
        --name "$VM_NAME" \
        --memory "$MEMORY" \
        --cores "$CORES" \
        --cpu "$CPU" \
        --net0 virtio,bridge=vmbr0 \
        --machine "$Q35_VERSION" \
        --scsihw virtio-scsi-single

    # Clean up default SCSI/IDE config if present
    qm config "$VM_ID" | grep -q "^scsi0:" && qm set "$VM_ID" --delete scsi0
    qm config "$VM_ID" | grep -q "^ide0:" && qm set "$VM_ID" --delete ide0
    qm config "$VM_ID" | grep -q "^ide2:" && qm set "$VM_ID" --delete ide2

    # Import disk image
    IMPORT_OUTPUT=$(qm importdisk "$VM_ID" "$NEW_IMG_FILE" "$STORAGE")
    VOLUME_ID=$(echo "$IMPORT_OUTPUT" | grep -oP "(?<=successfully imported disk ')[^']+")

    if [ -z "$VOLUME_ID" ]; then
        echo -e "${R}[!] Failed to extract volume ID from import output.${X}"
        echo -e "${R}Output: $IMPORT_OUTPUT${X}"
        exit 1
    fi

    # Attach imported disk to SATA0
    qm set "$VM_ID" --sata0 "$VOLUME_ID"

    # Configure boot and QEMU agent
    qm set "$VM_ID" \
        --agent enabled=1 \
        --boot order=sata0 \
        --bootdisk sata0 \
        --onboot 1 

    # VM description
    NOTES_HTML=$(vm_notes_html)
    qm set "$VM_ID" --description "$NOTES_HTML"

} > /dev/null 2>&1 &

SPINNER_PID=$!
show_spinner $SPINNER_PID

# Final step
create_header "vDSM-Arc-Install"

# Ask to delete temp file
confirm_delete_temp_file
line

# Success message
echo -e "${G}[OK] ${C}$VM_NAME (ID: $VM_ID) has been successfully created!${X}"
echo -e "${G}[OK] ${C}SATA0: img (${NEW_IMG_FILE})${X}"
line

# Optional: disk configuration menu
sata_disk_menu