<p align="left">
  <a href="https://github.com/vdarkobar/Home-Cloud/blob/main/README.md#create-samba-file-server">Home</a>
</p>  

  
# Samba
File server  

  
Clone <a href="https://github.com/vdarkobar/DebianTemplate/blob/main/README.md#debian-template">Template</a>, SSH in using <a href="https://github.com/vdarkobar/Home-Cloud/blob/main/shared/Bastion.md#bastion">Bastion Server</a>  

  
Don't forget to add free space to cloned VM:  
> *VM Name > Hardware > Hard Disk > Disk Action > Resize*  
  
### *Run this command*:
```
bash -c "$(wget -qLO - https://raw.githubusercontent.com/vdarkobar/Samba/main/setup.sh)"
```

```
bash -c "$(wget -qLO - https://raw.githubusercontent.com/vdarkobar/Samba/main/setup-ct.sh)"
```
<br><br>
*(steps used to configure <a href="https://github.com/vdarkobar/Samba/blob/main/steps.md">Samba</a>)*
