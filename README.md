# SSH File Transfer GUI

`ssh-file-transfer.sh` is a bash script that provides a graphical user interface (GUI) for securely transferring files and directories to a remote SSH server. The script uses Zenity to prompt for credentials, select files or directories, and manage the file transfer process.

## Features
- Simple GUI for SSH connection setup
- File and directory selection with Zenity file manager
- Secure file transfer with progress display
- Automatic continuation without requiring "OK" confirmations during transfer

## Requirements
The script requires the following dependencies:
- **Zenity** for GUI dialogs
- **sshpass** for password-based SSH connection
- **openssh-server** for SSH connection

## Dependencies Installation & Script Execution

Run this command to install required dependencies on Debian/Ubuntu and then run the script:

```bash
sudo apt update && sudo apt install -y zenity sshpass openssh-server
git clone https://github.com/GlitchLinux/ssh-file-transfer.sh.git
cd ssh-file-transfer.sh
chmod +x ssh-file-transfer.sh
bash ssh-file-transfer.sh
