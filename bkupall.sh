#!/bin/bash

# Function to select backup destination
choose_backup_path() {
    echo "Please enter the backup path (e.g., /mnt/backup):"
    read -p "Backup Path: " BACKUP_PATH

    # Check if the directory exists, if not, create it
    if [ ! -d "$BACKUP_PATH" ]; then
        echo "Directory does not exist. Creating it now..."
        mkdir -p "$BACKUP_PATH"
    fi
}

# Function to back up VMs
backup_vms() {
    echo "Backing up all VMs..."
    # List all VMs (you can filter for specific VMs if needed)
    VM_IDS=$(qm list | awk 'NR>1 {print $1}')
    
    for VMID in $VM_IDS; do
        echo "Backing up VM $VMID..."
        vzdump $VMID --dumpdir $BACKUP_PATH --mode snapshot --compress lzo --node $(hostname) --storage local
    done
}

# Function to back up LXC containers
backup_lxcs() {
    echo "Backing up all LXC containers..."
    # List all containers (you can filter for specific containers if needed)
    CT_IDS=$(pct list | awk 'NR>1 {print $1}')
    
    for CTID in $CT_IDS; do
        echo "Backing up LXC container $CTID..."
        vzdump $CTID --dumpdir $BACKUP_PATH --mode snapshot --compress lzo --node $(hostname)
    done
}

# Main script execution
echo "Welcome to Proxmox Backup Script"
choose_backup_path

# Optionally backup VMs or LXC containers
echo "What would you like to back up?"
echo "1. Back up all VMs"
echo "2. Back up all LXC containers"
echo "3. Back up both VMs and LXC containers"
read -p "Enter choice (1/2/3): " CHOICE

case $CHOICE in
    1)
        backup_vms
        ;;
    2)
        backup_lxcs
        ;;
    3)
        backup_vms
        backup_lxcs
        ;;
    *)
        echo "Invalid choice, exiting..."
        exit 1
        ;;
esac

echo "Backup completed. All backups are saved in $BACKUP_PATH."
