#!/bin/bash

clear

WORK_DIR=$(pwd)

##############################################################
# Define ANSI escape sequence for green, red and yellow font #
##############################################################

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'


########################################################
# Define ANSI escape sequence to reset font to default #
########################################################

NC='\033[0m'


#################
# Intro message #
#################

echo
echo -e "${GREEN} This script will install and configure${NC} Samba File Server"

sleep 0.5 # delay for 0.5 seconds
echo

echo -e "${GREEN} You'll be asked to enter: ${NC}"
echo -e " - Samba User name and Password ${NC}"
echo -e " - Samba Group ${NC}"
echo -e "${GREEN}   to determin ownership for the${NC} shares."
echo
echo -e "${GREEN} - Additional Users and/or Groups or Share Definitions can be added later, on the Server. ${NC}"
echo


#######################################
# Prompt user to confirm script start #
#######################################

while true; do
    echo -e "${GREEN} Start installation and configuration?${NC} (yes/no) "
    echo
    read choice
    echo
    choice=$(echo "$choice" | tr '[:upper:]' '[:lower:]') # Convert input to lowercase

    # Check if user entered "yes"
    if [[ "$choice" == "yes" ]]; then
        # Confirming the start of the script
        echo
        echo -e "${GREEN} Starting... ${NC}"
        sleep 0.5 # delay for 0.5 second
        echo
        break

    # Check if user entered "no"
    elif [[ "$choice" == "no" ]]; then
        echo -e "${RED} Aborting script. ${NC}"
        exit

    # If user entered anything else, ask them to correct it
    else
        echo -e "${YELLOW} Invalid input. Please enter${NC} 'yes' or 'no'"
        echo
    fi
done


#################
# Install Samba #
#################

echo -e "${GREEN} Installing Samba and other packages ${NC}"

sleep 0.5 # delay for 0.5 seconds
echo

if ! sudo apt install -y samba smbclient cifs-utils; then
    echo -e "${RED} Failed to install packages. Exiting. ${NC}"
    exit 1
fi


#######################
# Create backup files #
#######################

echo
echo -e "${GREEN} Creating backup files ${NC}"

sleep 0.5 # delay for 0.5 seconds
echo

# Backup the existing /etc/hosts file
if [ ! -f /etc/hosts.backup ]; then
    sudo cp /etc/hosts /etc/hosts.backup
    echo -e "${GREEN} Backup of${NC} /etc/hosts ${GREEN}created.${NC}"
else
    echo -e "${YELLOW} Backup of${NC} /etc/hosts ${YELLOW}already exists. Skipping backup.${NC}"
fi

# Backup original /etc/cloud/cloud.cfg file before modifications
CLOUD_CFG="/etc/cloud/cloud.cfg"
if [ ! -f "$CLOUD_CFG.bak" ]; then
    sudo cp "$CLOUD_CFG" "$CLOUD_CFG.bak"
    echo -e "${GREEN} Backup of${NC} $CLOUD_CFG ${GREEN}created.${NC}"
else
    echo -e "${YELLOW} Backup of${NC} $CLOUD_CFG ${YELLOW}already exists. Skipping backup.${NC}"
fi

# Before modifying Unbound configuration files, create backups if they don't already exist

SAMBA_FILES=(
    "/etc/samba/smb.conf"
)

for file in "${SAMBA_FILES[@]}"; do
    if [ ! -f "$file.backup" ]; then
        sudo cp "$file" "$file.backup"
        echo -e "${GREEN} Backup of${NC} $file ${GREEN}created.${NC}"
    else
        echo -e "${YELLOW} Backup of${NC} $file ${YELLOW}already exists. Skipping backup.${NC}"
    fi
done


#######################
# Edit cloud.cfg file #
#######################

echo
echo -e "${GREEN} Preventing Cloud-init of rewritining${NC} hosts file "

sleep 0.5 # delay for 0.5 seconds
echo

# Define the file path
FILE_PATH="/etc/cloud/cloud.cfg"

# Comment out the specified modules
sudo sed -i '/^\s*- set_hostname/ s/^/#/' "$FILE_PATH"
sudo sed -i '/^\s*- update_hostname/ s/^/#/' "$FILE_PATH"
sudo sed -i '/^\s*- update_etc_hosts/ s/^/#/' "$FILE_PATH"

echo -e "${GREEN} Modifications to${NC} $FILE_PATH ${GREEN}applied successfully.${NC}"


######################
# Prepare hosts file #
######################

echo
echo -e "${GREEN} Setting up hosts file ${NC}"

sleep 0.5 # delay for 0.5 seconds
echo

# Extract the domain name from /etc/resolv.conf
domain_name=$(awk -F' ' '/^domain/ {print $2; exit}' /etc/resolv.conf)

# Get the host's IP address and hostname
host_ip=$(hostname -I | awk '{print $1}')
host_name=$(hostname)

# Construct the new line for /etc/hosts
new_line="$host_ip $host_name $host_name.$domain_name"

# Create a temporary file with the desired contents
{
    echo "# Your system has configured 'manage_etc_hosts' as True."
    echo "# As a result, if you wish for changes to this file to persist"
    echo "# then you will need to either"
    echo "# a.) make changes to the master file in /etc/cloud/templates/hosts.debian.tmpl"
    echo "# b.) change or remove the value of 'manage_etc_hosts' in"
    echo "# /etc/cloud/cloud.cfg or cloud-config from user-data"
    echo ""
    echo "$new_line"
    echo "============================================"
    # Replace the line containing the current hostname with the new line
    awk -v hostname="$host_name" -v new_line="$new_line" '!($0 ~ hostname) || $0 == new_line' /etc/hosts
} > /tmp/hosts.tmp

# Move the temporary file to /etc/hosts
sudo mv /tmp/hosts.tmp /etc/hosts

echo -e "${GREEN} File${NC} /etc/hosts ${GREEN}has been updated ${NC}"


####################
# Prepare firewall #
####################

echo
echo -e "${GREEN} Preparing firewall ${NC}"

sleep 0.5 # delay for 0.5 seconds
echo

sudo ufw allow Samba && \
sudo systemctl restart ufw
echo


######################################
# Set User/Group/Folders/Premissions #
######################################

# Create directories
if ! sudo mkdir -p /public || ! sudo mkdir -p /private; then
    echo -e "${RED} Error: Failed to create directories. ${NC}"
    exit 1
fi

# Set permissions
if ! sudo chmod 2770 /private; then
    echo -e "${RED} Error: Failed to set permissions on${NC} /private"
    exit 1
fi

if ! sudo chmod 2775 /public; then
    echo -e "${RED} Error: Failed to set permissions on${NC} /public"
    exit 1
fi

echo -e "${GREEN} Directories${NC} /public ${GREEN}and${NC} /private${NC} ${GREEN}are configured with the correct permissions${NC}"
echo

# Get valid Samba user name with error correction, existing user check, and repetition
while true; do
    read -p "Enter the Samba user name: " SMB_USER

    # Input validation
    if [[ -z "${SMB_USER}" ]]; then  # Check if input is empty
        echo -e "${YELLOW} Input cannot be empty. Please try again. ${NC}"
    elif [[ ! "${SMB_USER}" =~ ^[a-zA-Z0-9]+$ ]]; then # Basic sanitization
        echo -e "${YELLOW} Group name can only contain letters, numbers. Please try again. ${NC}"
    else
        # Get existing user names for validation
        existing_users=$(sudo getent group | awk -F: '{print $1}' | paste -sd, -)

        if [[ ",$existing_users," =~ ",$SMB_USER," ]]; then  # Check against existing users
            echo -e "${YELLOW} User name already exists. Please choose a different name.${NC}"
        else
            # User name is valid, proceed with the rest of your actions
            echo "$SMB_USER" > "smb-user-name.txt" 
            break # Exit the loop since we have a valid group name
        fi
    fi
done

# Create Samba user
if ! sudo useradd -M -s /sbin/nologin "${SMB_USER}"; then
    echo -e "${RED} Error: Failed to create Samba user. Please check if the user already exists. ${NC}"
    exit 1
fi

# Add password to user
if ! sudo smbpasswd -a "${SMB_USER}"; then
    echo -e "${RED} Error: Failed to add password to user. ${NC}"
    exit 1
fi

# Activate user
if ! sudo smbpasswd -e "${SMB_USER}"; then
    echo -e "${RED} Error: Failed to enable user. ${NC}"
    exit 1
fi

# Get valid Samba group name with error correction, existing group check, and repetition
while true; do
    read -p "Enter the Samba group name: " SMB_GROUP

    # Input validation
    if [[ -z "${SMB_GROUP}" ]]; then  # Check if input is empty
        echo -e "${YELLOW} Input cannot be empty. Please try again.${NC}"
    elif [[ ! "${SMB_GROUP}" =~ ^[a-zA-Z0-9]+$ ]]; then # Basic sanitization
        echo -e "${YELLOW} Group name can only contain letters, numbers, underscores, and hyphens. Please try again.${NC}"
    else
        # Get existing group names for validation
        existing_groups=$(sudo getent group | awk -F: '{print $1}' | paste -sd, -)

        if [[ ",$existing_groups," =~ ",$SMB_GROUP," ]]; then  # Check against existing groups
            echo -e "${YELLOW} Group name already exists. Please choose a different name.${NC}"
        else
            # Group name is valid, proceed with the rest of your actions
            echo "$SMB_GROUP" > "smb-group-name.txt" 
            break # Exit the loop since we have a valid group name
        fi
    fi
done

# Create Samba group
if ! sudo groupadd "${SMB_GROUP}"; then
    echo -e "${RED} Error: Failed to create Samba group. Please check if the group already exists. ${NC}"
    exit 1
fi

# Change group ownership
if ! sudo chgrp -R "${SMB_GROUP}" /private; then
    echo -e "${RED} Error: Failed to change group ownership of${NC} /private"
    exit 1
fi

if ! sudo chgrp -R "${SMB_GROUP}" /public; then
    echo -e "${RED} Error: Failed to change group ownership of${NC} /public "
    exit 1
fi

echo
echo -e "${GREEN} Directories${NC} /public ${GREEN}and${NC} /private ${GREEN}are configured with the correct ownership.${NC}"
echo

# Add user to group
if ! sudo usermod -aG "${SMB_GROUP}" "${SMB_USER}"; then
    echo -e "${RED} Error: Failed to add user to group. ${NC}"
    exit 1
fi

# Modify smb.conf with fallback to smb-group-name.txt
if ! sudo sed -i "s:SMB_GROUP_HERE:$SMB_GROUP:g" smb.conf; then
    # Initial replacement failed, check if smb-group-name.txt exists
    if [ -f "smb-group-name.txt" ]; then
        fallback_group=$(head -n 1 smb-group-name.txt)  # Read the first line

        # Attempt replacement with group name from the file
        if sudo sed -i "s:SMB_GROUP_HERE:$fallback_group:g" smb.conf; then
            echo -e "${YELLOW} Placeholder replaced with group name extracted from${NC} smb-group-name.txt"
        else
            echo -e "${RED} Error: Failed to update Samba configuration even with fallback. ${NC}"
            exit 1
        fi
    else
        echo -e "${RED} Error: Failed to update Samba configuration and smb-group-name.txt not found. ${NC}"
        exit 1
    fi
fi

# Check if the placeholder was replaced even after potential fallback
if grep -q "SMB_GROUP_HERE" smb.conf; then
    echo -e "${RED} Error: Placeholder was not replaced. Please check your smb.conf file. ${NC}"
    exit 1
else
    echo -e "${GREEN} Samba configuration updated. ${NC}"
fi

echo


##############################
# Replace configuration file #
##############################

echo -e "${GREEN} Replacing existing Samba configuration file${NC} smb.conf"

sleep 0.5 # delay for 0.5 seconds
echo

sudo cp smb.conf /etc/samba/smb.conf
if [ $? -ne 0 ]; then
    echo -e "${RED} Error: Failed to copy${NC} smb.conf ${RED}to${NC} /etc/samba/smb.conf"
    exit 1
fi


######################
# Info before reboot #
######################

IP_ADDRESS=$(hostname -I | awk '{print $1}')

# Extract the domain name from /etc/resolv.conf
domain_name=$(awk -F' ' '/^domain/ {print $2; exit}' /etc/resolv.conf)
# Get the host's IP address and hostname
host_ip=$(hostname -I | awk '{print $1}')
host_name=$(hostname)
# Construct the new line for /etc/hosts
new_line="$host_ip $host_name $host_name.$domain_name"

echo -e "${GREEN} REMEMBER: ${NC}"
sleep 0.5 # delay for 0.5 seconds
echo

echo -e "${GREEN} This configuration creates two shared folders: ${NC}"
echo -e 
echo -e " /public - ${GREEN}for Limited Guest Access (Read only) ${NC}"
echo -e " /private - ${GREEN} owned by Samba group:${NC} $SMB_GROUP ${GREEN}with the following member:${NC} $SMB_USER"
echo
echo -e "${GREEN} Username to access private Samba share:${NC} $SMB_USER"
echo
echo -e "${GREEN} To list what Samba services are available on the server:${NC}"
echo -e "smbclient -L //$IP_ADDRESS/ -U $SMB_USER"
echo -e "smbclient -L //$HOST_NAME.$DOMAIN_NAME/ -U $SMB_USER"
echo
echo -e "${GREEN} Test access to the share at: ${NC}"
echo
echo -e "${GREEN} Linux: ${NC}"
echo "smbclient '\\\\localhost\\private' -U $SMB_USER"
echo "smbclient '\\\\localhost\\public' -U $SMB_USER"
echo "smbclient '\\\\$IP_ADDRESS\\private' -U $SMB_USER"
echo "smbclient '\\\\$IP_ADDRESS\\public' -U $SMB_USER"
echo "smbclient '\\\\$HOST_NAME.$DOMAIN_NAME\\private' -U $SMB_USER"
echo "smbclient '\\\\$HOST_NAME.$DOMAIN_NAME\\public' -U $SMB_USER"
echo
echo -e "${GREEN} on Windows: ${NC}"
echo "\\\\$IP_ADDRESS"
echo "\\\\$HOST_NAME.$DOMAIN_NAME"
echo


##########################
# Prompt user for reboot #
##########################

while true; do
    read -p "Do you want to reboot the server now (recommended)? (yes/no): " response
    echo
    case "${response,,}" in
        yes|y) echo -e "${GREEN} Rebooting the server...${NC}"; sudo reboot; break ;;
        no|n) echo -e "${RED} Reboot cancelled.${NC}"; exit 0 ;;
        *) echo -e "${YELLOW} Invalid response. Please answer${NC} yes or no."; echo ;;
    esac
done


####################################
# Remove Script(s) from the system #
####################################

echo
echo -e "${RED} This Script Will Self Destruct!${NC}"
echo
cd ~
sudo rm -rf $WORK_DIR
