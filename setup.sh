#!/bin/bash

clear

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
echo -e "${GREEN} This script will install and configure Samba ${NC}"

sleep 0.5 # delay for 0.5 seconds
echo

echo -e "${GREEN} - You'll be asked to enter: ${NC}"
echo -e "${GREEN} - Samba Username and Samba Group, ${NC}"
echo -e "${GREEN} - to determin ownership for the Shares. ${NC}"
echo

######################################
# Prompt user to confirm script start#
######################################
while true; do
    echo -e "${GREEN}Start Samba installation and configuration? (y/n) ${NC}"
    read choice

    # Check if user entered "y" or "Y"
    if [[ "$choice" == [yY] ]]; then

        # Confirming the start of the script
        echo -e "${GREEN}Starting... ${NC}"
        sleep 0.5 # delay for 0.5 second
        echo
        break

    # If user entered "n" or "N", exit the script
    elif [[ "$choice" == [nN] ]]; then
        echo -e "${RED}Aborting script. ${NC}"
        exit

    # If user entered anything else, ask them to correct it
    else
        echo -e "${YELLOW}Invalid input. Please enter 'y' or 'n'. ${NC}"
    fi
done


###################
# Install Samba #
###################
echo -e "${GREEN} Installing Samba and other packages ${NC}"

sleep 0.5 # delay for 0.5 seconds
echo

if ! sudo apt install -y samba smbclient cifs-utils; then
    echo "Failed to install packages. Exiting."
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
    echo -e "${GREEN}Backup of /etc/hosts created.${NC}"
else
    echo -e "${YELLOW}Backup of /etc/hosts already exists. Skipping backup.${NC}"
fi

# Backup original /etc/cloud/cloud.cfg file before modifications
CLOUD_CFG="/etc/cloud/cloud.cfg"
if [ ! -f "$CLOUD_CFG.bak" ]; then
    sudo cp "$CLOUD_CFG" "$CLOUD_CFG.bak"
    echo -e "${GREEN}Backup of $CLOUD_CFG created.${NC}"
else
    echo -e "${YELLOW}Backup of $CLOUD_CFG already exists. Skipping backup.${NC}"
fi

# Before modifying Unbound configuration files, create backups if they don't already exist

SAMBA_FILES=(
    "/etc/samba/smb.conf"
)

for file in "${SAMBA_FILES[@]}"; do
    if [ ! -f "$file.backup" ]; then
        sudo cp "$file" "$file.backup"
        echo -e "${GREEN}Backup of $file created.${NC}"
    else
        echo -e "${YELLOW}Backup of $file already exists. Skipping backup.${NC}"
    fi
done


#######################
# Edit cloud.cfg file #
#######################
echo
echo -e "${GREEN} Preventing Cloud-init of rewritining hosts file ${NC}"

sleep 0.5 # delay for 0.5 seconds
echo

# Define the file path
FILE_PATH="/etc/cloud/cloud.cfg"

# Comment out the specified modules
sudo sed -i '/^\s*- set_hostname/ s/^/#/' "$FILE_PATH"
sudo sed -i '/^\s*- update_hostname/ s/^/#/' "$FILE_PATH"
sudo sed -i '/^\s*- update_etc_hosts/ s/^/#/' "$FILE_PATH"

echo -e "${GREEN}Modifications to $FILE_PATH applied successfully.${NC}"


######################
# Prepare hosts file #
######################
echo
echo -e "${GREEN} Setting up hosts file ${NC}"

sleep 0.5 # delay for 0.5 seconds
echo

# Extract the domain name from /etc/resolv.conf
DOMAIN_NAME=$(grep '^domain' /etc/resolv.conf | awk '{print $2}')

# Check if DOMAIN_NAME has a value
if [ -z "$DOMAIN_NAME" ]; then
    echo "${RED}Could not determine the domain name from /etc/resolv.conf. Skipping operations that require the domain name.${NC}"
else
    # Continue with operations that require DOMAIN_NAME
    # Identify the host's primary IP address and hostname
    HOST_IP=$(hostname -I | awk '{print $1}')
    HOST_NAME=$(hostname)

    # Skip /etc/hosts update if HOST_IP or HOST_NAME are not determined
    if [ -z "$HOST_IP" ] || [ -z "$HOST_NAME" ]; then
        echo -e "${RED}Could not determine the host IP address or hostname. Skipping /etc/hosts update${NC}"
    else
        # Display the extracted domain name, host IP, and hostname
        echo -e "${GREEN}Domain name: $DOMAIN_NAME${NC}"
        echo -e "${GREEN}Host IP: $HOST_IP${NC}"
        echo -e "${GREEN}Hostname: $HOST_NAME${NC}"

        # Remove any existing lines with the current hostname in /etc/hosts
        sudo sed -i "/$HOST_NAME/d" /etc/hosts

        # Prepare the new line in the specified format
        NEW_LINE="$HOST_IP"$'\t'"$HOST_NAME $HOST_NAME.$DOMAIN_NAME"

        # Insert the new line directly below the 127.0.0.1 localhost line
        sudo awk -v newline="$NEW_LINE" '/^127.0.0.1 localhost$/ { print; print newline; next }1' /etc/hosts | sudo tee /etc/hosts.tmp > /dev/null && sudo mv /etc/hosts.tmp /etc/hosts
        echo
        echo -e "${GREEN}File /etc/hosts has been updated.${NC}"
    fi

    # Continue with any other operations that require DOMAIN_NAME
fi


#############################
# Modify dhclient.conf file #
#############################
echo
echo -e "${GREEN}Modifying dhclient.conf file (automaticaly overwriting resolve.conf) ${NC}"

sleep 0.5 # delay for 0.5 seconds
echo

# Path to the dhclient.conf file
DHCLIENT_CONF="/etc/dhcp/dhclient.conf"

# Check if the dhclient.conf file exists
if [ ! -f "$DHCLIENT_CONF" ]; then
    echo -e "${RED}Error: $DHCLIENT_CONF does not exist. ${NC}"
    exit 1
fi

# Backup the original file before making changes
sudo cp $DHCLIENT_CONF "${DHCLIENT_CONF}.bak"
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to backup the original dhclient.conf file. ${NC}"
    exit 1
fi

# Replace the specified lines
sudo sed -i 's/domain-name, domain-name-servers, domain-search, host-name,/domain-name, domain-search, host-name,/' $DHCLIENT_CONF
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to replace the first specified line. ${NC}"
    exit 1
fi

sudo sed -i 's/dhcp6.name-servers, dhcp6.domain-search, dhcp6.fqdn, dhcp6.sntp-servers,/dhcp6.domain-search, dhcp6.fqdn, dhcp6.sntp-servers,/' $DHCLIENT_CONF
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to replace the second specified line. ${NC}"
    exit 1
fi

# Get the primary IP address of the machine
IP_ADDRESS=$(hostname -I | awk '{print $1}')
if [ -z "$IP_ADDRESS" ]; then
    echo -e "${RED}Error: Failed to obtain the IP address of the machine. ${NC}"
    exit 1
fi

# Check and replace the "prepend domain-name-servers" line with the machine's IP address
sudo sed -i "/^#prepend domain-name-servers 127.0.0.1;/a prepend domain-name-servers ${IP_ADDRESS};" $DHCLIENT_CONF
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to insert the machine's IP address. ${NC}"
    exit 1
fi

# Now, find the line with the machine's IP address and add the 127.0.0.1 below it
sudo sed -i "/^prepend domain-name-servers ${IP_ADDRESS};/a prepend domain-name-servers 127.0.0.1;" $DHCLIENT_CONF
if [ $? -ne 0 ]; then
    echo -e "${RED}Error: Failed to insert the 127.0.0.1 address below the machine's IP address. ${NC}"
    exit 1
fi

echo -e "${GREEN}Modifications completed successfully. ${NC}"


####################
# Prepare firewall #
####################
echo
echo -e "${GREEN} Preparing firewall ${NC}"

sleep 0.5 # delay for 0.5 seconds
echo

sudo ufw allow Samba && \
sudo systemctl restart ufw


######################################
# Set User/Group/Folders/Premissions #
######################################

# Initialize variables
#SMB_GROUP=""
#SMB_USER=""

# Create directories
if ! sudo mkdir -p /public || ! sudo mkdir -p /private; then
    echo "Error: Failed to create directories."
    exit 1
fi

# Set permissions
if ! sudo chmod 2770 /private; then
    echo "Error: Failed to set permissions on /private."
    exit 1
fi

if ! sudo chmod 2775 /public; then
    echo "Error: Failed to set permissions on /public."
    exit 1
fi

echo "Directories /public and /private are configured with the correct permissions"

# Get valid Samba user name with error correction, existing user check, and repetition
while true; do
    read -p "Enter the Samba user name: " SMB_USER

    # Input validation
    if [[ -z "${SMB_USER}" ]]; then  # Check if input is empty
        echo "Input cannot be empty. Please try again."
    elif [[ ! "${SMB_USER}" =~ ^[a-zA-Z0-9]+$ ]]; then # Basic sanitization
        echo "Group name can only contain letters, numbers. Please try again."
    else
        # Get existing user names for validation
        existing_users=$(sudo getent group | awk -F: '{print $1}' | paste -sd, -)

        if [[ ",$existing_users," =~ ",$SMB_USER," ]]; then  # Check against existing users
            echo "User name already exists. Please choose a different name."
        else
            # User name is valid, proceed with the rest of your actions
            echo "$SMB_USER" > "smb-user-name.txt" 
            break # Exit the loop since we have a valid group name
        fi
    fi
done

# Create Samba user
if ! sudo useradd -M -s /sbin/nologin "${SMB_USER}"; then
    echo "Error: Failed to create Samba user. Please check if the user already exists."
    exit 1
fi

# Add password to user
if ! sudo smbpasswd -a "${SMB_USER}"; then
    echo "Error: Failed to add password to user."
    exit 1
fi

# Activate user
if ! sudo smbpasswd -e "${SMB_USER}"; then
    echo "Error: Failed to enable user."
    exit 1
fi

# Get valid Samba group name with error correction, existing group check, and repetition
while true; do
    read -p "Enter the Samba group name: " SMB_GROUP

    # Input validation
    if [[ -z "${SMB_GROUP}" ]]; then  # Check if input is empty
        echo "Input cannot be empty. Please try again."
    elif [[ ! "${SMB_GROUP}" =~ ^[a-zA-Z0-9]+$ ]]; then # Basic sanitization
        echo "Group name can only contain letters, numbers, underscores, and hyphens. Please try again."
    else
        # Get existing group names for validation
        existing_groups=$(sudo getent group | awk -F: '{print $1}' | paste -sd, -)

        if [[ ",$existing_groups," =~ ",$SMB_GROUP," ]]; then  # Check against existing groups
            echo "Group name already exists. Please choose a different name."
        else
            # Group name is valid, proceed with the rest of your actions
            echo "$SMB_GROUP" > "smb-group-name.txt" 
            break # Exit the loop since we have a valid group name
        fi
    fi
done

# Create Samba group
if ! sudo groupadd "${SMB_GROUP}"; then
    echo "Error: Failed to create Samba group. Please check if the group already exists."
    exit 1
fi

# Change group ownership
if ! sudo chgrp -R "${SMB_GROUP}" /private; then
    echo "Error: Failed to change group ownership of /private."
    exit 1
fi

if ! sudo chgrp -R "${SMB_GROUP}" /public; then
    echo "Error: Failed to change group ownership of /public."
    exit 1
fi

echo "Directories /public and /private are configured with the correct ownership."

# Add user to group
if ! sudo usermod -aG "${SMB_GROUP}" "${SMB_USER}"; then
    echo "Error: Failed to add user to group."
    exit 1
fi

# Modify smb.conf with fallback to smb-group-name.txt
if ! sudo sed -i "s:SMB_GROUP_HERE:$SMB_GROUP:g" smb.conf; then
    # Initial replacement failed, check if smb-group-name.txt exists
    if [ -f "smb-group-name.txt" ]; then
        fallback_group=$(head -n 1 smb-group-name.txt)  # Read the first line

        # Attempt replacement with group name from the file
        if sudo sed -i "s:SMB_GROUP_HERE:$fallback_group:g" smb.conf; then
            echo "Placeholder replaced with group name from smb-group-name.txt"
        else
            echo "Error: Failed to update Samba configuration even with fallback."
            exit 1
        fi
    else
        echo "Error: Failed to update Samba configuration and smb-group-name.txt not found."
        exit 1
    fi
fi

# Check if the placeholder was replaced even after potential fallback
if grep -q "SMB_GROUP_HERE" smb.conf; then
    echo "Error: Placeholder was not replaced. Please check your smb.conf file."
    exit 1
else
    echo "Samba configuration updated. You may need to restart the Samba service (e.g., sudo service smbd restart)."
fi


##############################
# Replace configuration file #
##############################
echo -e "${GREEN}Replacing existing Unbound configuration file (unbound.conf) ${NC}"

sleep 0.5 # delay for 0.5 seconds
echo

sudo cp smb.conf /etc/samba/smb.conf
if [ $? -ne 0 ]; then
    echo "Error: Failed to copy smb.conf to /etc/samba/smb.conf"
    exit 1
fi


##########################
# Info before reboot #
##########################

echo -e "${GREEN}REMEMBER: ${NC}"
echo
sleep 0.5 # delay for 0.5 seconds
echo

echo -e "This configuration creates two shared folders:"
echo -e 
echo -e "/public - for Limited Guest Access (Read only)"
echo -e "/private - owned by Samba group: $SMB_GROUP with the following member: $SMB_USER"
echo
echo -e "Username to access private Samba share: $SMB_USER"
echo
echo -e "To list what services are available on a Samba server"
echo
echo -e "smbclient -L //$IP_ADDRESS/ -U $SMB_USER"
echo
echo
echo -e "Test access to the share at:"
echo
echo -e "Linux:"
echo -e "smbclient '\\localhost\private' -U $SMB_USER"
echo -e "smbclient '\\localhost\public' -U $SMB_USER"
echo -e "smbclient '\\$IP_ADDRESS\private' -U $SMB_USER"
echo -e "smbclient '\\$IP_ADDRESS\public' -U $SMB_USER"
echo -e "smbclient '\\$HOST_NAME.$DOMAIN_NAME\private' -U $SMB_USER"
echo -e "smbclient '\\$HOST_NAME.$DOMAIN_NAME\public' -U $SMB_USER"
echo
echo -e "on Windows:"
echo -e "\\$IP_ADDRESS"
echo -e "\\$HOST_NAME.$DOMAIN_NAME"
echo


##########################
# Prompt user for reboot #
##########################

while true; do
    read -p "Do you want to reboot the server now (recommended)? (yes/no): " response
    case "${response,,}" in
        yes|y) echo -e "${GREEN}Rebooting the server...${NC}"; sudo reboot; break ;;
        no|n) echo -e "${RED}Reboot cancelled.${NC}"; exit 0 ;;
        *) echo -e "${YELLOW}Invalid response. Please answer${NC} yes or no." ;;
    esac
done
