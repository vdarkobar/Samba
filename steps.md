
<a href="https://github.com/vdarkobar/Samba/tree/main?tab=readme-ov-file#samba">Back</a>
<br><br>

## Samba  
  

Install Samba Packages
```
sudo apt install -y samba smbclient cifs-utils
```
```
sudo systemctl status smbd
```
```
smbstatus --version
```

Backup configuration file
```
sudo cp smb.conf smb.conf.backup
```

Samba configuration file
```
sudo nano /etc/samba/smb.conf
```

Create Shared Samba Directories
```
sudo mkdir /public
```
```
sudo mkdir /private
```

Samba share user group
```
sudo groupadd smbshare
```

Add the necessary group permissions for the private share.
```
sudo chgrp -R smbshare /private
```
```
sudo chgrp -R smbshare /public
```

Set the right directory permissions.
```
sudo chmod 2770 /private
```
```
sudo chmod 2775 /public
```

Create a no login local user to access the private share.
```
sudo useradd -M -s /sbin/nologin sambauser
```

Add the user to the Samba share group created above.
```
sudo usermod -aG smbshare sambauser
```

Create an SMB password for the user.
```
sudo smbpasswd -a sambauser
```

Enable the created account:
```
sudo smbpasswd -e sambauser
```

Verify the Samba configuration
```
sudo testparm
```

Restart the Samba service
```
sudo systemctl restart smbd
```

Allow Samba traffic (Ports: 137,138/udp, 139,445/tcp)
```
sudo ufw allow Samba
```
```
sudo ufw app info Samba
```

Or, allow remote access from the specified IP range to Samba (more secure)
```
sudo ufw allow from 192.168.30.0/24 to any app Samba
```

Create demo files in the Samba shares, try accessing the share from your local machine
```
sudo mkdir /private/demo-private /public/demo-public && \
sudo touch /private/demo1.txt /public/demo2.txt
```
```
smbclient '\\localhost\private' -U sambauser
```
```
ls
```

To set up a Linux client, you will need Samba packages:
```
sudo apt install samba-client cifs-utils
```

Once installed, navigate to File manager->Other locations and add your share using the syntax below.
```
smb://servername/Share_name
```
