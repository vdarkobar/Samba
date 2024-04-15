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
echo -e "${GREEN} This script will install and configure${NC} Samba File Server"
echo
echo -e "${GREEN} Be sure that you are logged in as a${NC} non-root ${GREEN}user and that user is added to the${NC} sudo ${GREEN}group"${NC}

sleep 0.5 # delay for 0.5 seconds
echo

echo -e "${GREEN} You'll be asked to enter: ${NC}"
echo -e " - Samba User name / Password ${NC}"
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


####################
# Install Packages #
####################

echo -e "${GREEN} Installing Samba and other packages ${NC}"

sleep 0.5 # delay for 0.5 seconds
echo

# Update the package repositories
if ! sudo apt update; then
    echo -e "${RED}Failed to update package repositories. Exiting.${NC}"
    exit 1
fi

# Install the necessary packages
if ! sudo apt install -y samba smbclient cifs-utils ufw; then
    echo -e "${RED}Failed to install packages. Exiting.${NC}"
    exit 1
fi


################################
# Setting up working directory #
################################

# Set the WORK_DIR variable
WORK_DIR=$(mktemp -d)

# Scrol to top
num_lines=$(tput lines)
echo -e "\033[${num_lines}A\033[0J"

echo
echo -e "${GREEN} Working directory:${NC} $WORK_DIR"
echo


########################
# Create smb.conf file #
########################

# Define the path to the directory and the file
file_path="$WORK_DIR/smb.conf"

# Check if the WORK_DIR variable is set
if [ -z "$WORK_DIR" ]; then
    echo -e "${RED} Error: WORK_DIR variable is not set${NC}"
    exit 1
fi

# Create or overwrite the smb.conf file, using sudo for permissions
echo -e "${GREEN} Creating Samba configuration file...:${NC} $file_path"

sudo tee "$file_path" > /dev/null <<EOF || { echo "Error: Failed to create $file_path"; exit 1; }
# Global parameters
[global]
workgroup = WORKGROUP
server string = Samba Server
server role = standalone server
# Consistent logging - consider a higher max log size (%m.log)
log file = /var/log/samba/log.%m
max log size = 5000
logging = file
panic action = /usr/share/samba/panic-action %d
obey pam restrictions = Yes
pam password change = Yes
unix password sync = Yes
passwd program = /usr/bin/passwd %u
passwd chat = *Enter\\snew\\s*\\spassword:* %n\\n *Retype\\snew\\s*\\spassword:* %n\\n *password\\supdated\\ssuccessfully* .
map to guest = Bad User
# Security Enhancements
smb encrypt = mandatory
client min protocol = SMB3
server min protocol = SMB3
idmap config * : backend = tdb
usershare allow guests = No
guest account = nobody
invalid users = root
# VFS Audit logging (adjust paths/settings as needed)
vfs objects = full_audit
full_audit:prefix = %u|%I|%m|%S
full_audit:success = mkdir rmdir open read write
full_audit:failure = none
full_audit:priority = NOTICE
# Recycle Bin Configuration
vfs objects = recycle
recycle:touch = yes
recycle:keeptree = yes
recycle:versions = yes
recycle:exclude_dir = tmp quarantine
# Share Definitions
[public]
comment = Public Folder for Limited Guest Access
path = /public
browseable = Yes
writable = No
guest ok = Yes
[private]
comment = private Folder
path = /private
# Valid user, in this case, is a group smbshare, add users to group to allow access
valid users = @SMB_GROUP_HERE
guest ok = No
writable = Yes
read only = No
# Security
force create mode = 0770
force directory mode = 0770
inherit permissions = Yes
EOF

# Check if the file was created successfully
if [ $? -ne 0 ]; then
    echo
    echo -e "${RED} Error: Failed to create${NC} $file_path"
    exit 1
fi

echo
echo -e "${GREEN} Samba configuration file created successfully:${NC} $file_path"
echo


#######################
# Create backup files #
#######################

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
    echo "$new_line"
    echo "============================================"
    # Replace the line containing the current hostname with the new line
    awk -v hostname="$host_name" -v new_line="$new_line" '!($0 ~ hostname) || $0 == new_line' /etc/hosts
} > /tmp/hosts.tmp

# Move the temporary file to /etc/hosts
sudo mv /tmp/hosts.tmp /etc/hosts

echo -e "${GREEN} File${NC} /etc/hosts ${GREEN}has been updated ${NC}"


##################
# Setting up UFW #
##################

echo -e "${GREEN} Setting up UFW...${NC}"
echo

# Limit SSH to Port 22/tcp
if ! sudo ufw limit 22/tcp comment "SSH"; then
    echo -e "${RED} Failed to limit SSH access. Exiting.${NC}"
    exit 1
fi

# Allow Samba
if ! sudo ufw allow Samba comment "Samba"; then
    echo -e "${RED} Failed to allow Samba. Exiting.${NC}"
    exit 1
fi

# Enable UFW without prompt
if ! sudo ufw --force enable; then
    echo -e "${RED} Failed to enable UFW. Exiting.${NC}"
    exit 1
fi

# Set global rules
if ! sudo ufw default deny incoming || ! sudo ufw default allow outgoing; then
    echo -e "${RED} Failed to set global rules. Exiting.${NC}"
    exit 1
fi

# Reload UFW to apply changes
if ! sudo ufw reload; then
    echo -e "${RED} Failed to reload UFW. Exiting.${NC}"
    exit 1
fi

echo
echo -e "${GREEN} UFW setup completed.${NC}"
sleep 0.5 # delay for 0.5 seconds
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
            echo "$SMB_USER" > "$WORK_DIR/smb-user-name.txt" 
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
            echo "$SMB_GROUP" > "$WORK_DIR/smb-group-name.txt" 
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
if ! sudo sed -i "s:SMB_GROUP_HERE:$SMB_GROUP:g" $file_path; then
    # Initial replacement failed, check if smb-group-name.txt exists
    if [ -f "smb-group-name.txt" ]; then
        fallback_group=$(head -n 1 smb-group-name.txt)  # Read the first line

        # Attempt replacement with group name from the file
        if sudo sed -i "s:SMB_GROUP_HERE:$fallback_group:g" $file_path; then
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
if grep -q "SMB_GROUP_HERE" $file_path; then
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

sudo cp $file_path /etc/samba/smb.conf
if [ $? -ne 0 ]; then
    echo -e "${RED} Error: Failed to copy${NC} $file_path ${RED}to${NC} /etc/samba/smb.conf"
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
new_line="$host_name.$domain_name"

num_lines=$(tput lines)
echo -e "\033[${num_lines}A\033[0J"

echo -e "${GREEN} REMEMBER: ${NC}"
sleep 0.5 # delay for 0.5 seconds
echo

echo -e "${GREEN} This configuration creates two shared folders: ${NC}"
echo -e 
echo -e " /public  - ${GREEN} for Limited Guest Access (Read only) ${NC}"
echo -e " /private - ${GREEN} owned by Samba group:${NC} $SMB_GROUP ${GREEN}with the following member:${NC} $SMB_USER"
echo
echo -e "${GREEN} Username to access private Samba share:${NC} $SMB_USER"
echo
echo -e "${GREEN} To list what Samba services are available on the server:${NC}"
echo -e "smbclient -L //$IP_ADDRESS/ -U $SMB_USER"
echo -e "smbclient -L //$new_line/ -U $SMB_USER"
echo
echo -e "${GREEN} Access to shares: ${NC}"
echo
echo -e "${GREEN} Linux: ${NC}"
echo "smbclient '\\\\localhost\\private' -U $SMB_USER"
echo "smbclient '\\\\localhost\\public' -U $SMB_USER"
echo "smbclient '\\\\$IP_ADDRESS\\private' -U $SMB_USER"
echo "smbclient '\\\\$IP_ADDRESS\\public' -U $SMB_USER"
echo "smbclient '\\\\$new_line\\private' -U $SMB_USER"
echo "smbclient '\\\\$new_line\\public' -U $SMB_USER"
echo
echo -e "${GREEN} on Windows: ${NC}"
echo "\\\\$IP_ADDRESS"
echo "\\\\$new_line"
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
