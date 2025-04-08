#!/bin/bash

# Function to display error and exit
error_exit() {
    if [ "$GUI_MODE" = true ]; then
        zenity --error --text="$1" --width=300
    else
        echo "ERROR: $1" >&2
    fi
    exit 1
}

# Function to test SSH connection
test_ssh_connection() {
    if [ "$GUI_MODE" = true ]; then
        if ! sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$username@$host" "exit" 2>&1 | \
           zenity --progress --title="Testing Connection" --text="Connecting to $host..." --percentage=0 --pulsate --auto-close; then
            error_exit "SSH connection failed!\n\nPossible reasons:\n1. Wrong credentials\n2. Server not reachable\n3. SSH service not running\n4. Firewall blocking port $port"
        fi
    else
        echo -n "Testing SSH connection to $host... "
        output=$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" -v "$username@$host" "exit" 2>&1)
        if [ $? -ne 0 ]; then
            echo "FAILED"
            echo "=== Debug Information ==="
            echo "$output"
            error_exit "SSH connection failed!\n\nCommon solutions:\n1. Verify username/password\n2. Check if SSH is running on port $port\n3. Ensure server is reachable\n4. Check firewall settings"
        fi
        echo "OK"
    fi
}

# Function to transfer files with sudo support
transfer_files() {
    local source_files=$1
    local destination=$2
    local use_sudo=$3

    if [ "$GUI_MODE" = true ]; then
        (
            echo "10"
            echo "# Preparing transfer..."
            echo "30"
            echo "# Starting file transfer..."
            
            if [ "$use_sudo" = true ]; then
                # Transfer to temp location first
                temp_dir="/tmp/ssh_transfer_$(date +%s)"
                transfer_output=$(sshpass -p "$password" scp -P "$port" -o StrictHostKeyChecking=no -r $source_files "$username@$host:$temp_dir" 2>&1)
                scp_exit=$?
                
                if [ $scp_exit -eq 0 ]; then
                    echo "50"
                    echo "# Moving files to final destination (sudo required)..."
                    # Move files with sudo
                    sudo_cmd="sudo mkdir -p $(dirname "$destination") && sudo mv $temp_dir/* $destination/ && sudo rm -rf $temp_dir"
                    transfer_output+=$'\n'$(sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$username@$host" "$sudo_cmd" 2>&1)
                    scp_exit=$?
                fi
            else
                # Direct transfer
                transfer_output=$(sshpass -p "$password" scp -P "$port" -o StrictHostKeyChecking=no -r $source_files "$username@$host:$destination" 2>&1)
                scp_exit=$?
            fi

            if [ $scp_exit -eq 0 ]; then
                echo "100"
                echo "# Transfer complete!"
            else
                echo "100"
                echo "# Transfer failed!"
                zenity --error --text="Transfer failed!\n\nError details:\n$transfer_output" --width=400
                exit 1
            fi
        ) | zenity --progress --title="File Transfer" --text="Starting transfer..." --percentage=0 --auto-close
    else
        echo -n "Transferring files... "
        spin='-\|/'
        i=0
        
        if [ "$use_sudo" = true ]; then
            # Transfer to temp location first
            temp_dir="/tmp/ssh_transfer_$(date +%s)"
            (sshpass -p "$password" scp -P "$port" -o StrictHostKeyChecking=no -r $source_files "$username@$host:$temp_dir" > .transfer_log 2>&1) &
            pid=$!
            
            while kill -0 $pid 2>/dev/null; do
                i=$(( (i+1) %4 ))
                printf "\rTransferring files to temp location... ${spin:$i:1}"
                sleep 0.1
            done
            
            wait $pid
            scp_exit=$?
            
            if [ $scp_exit -eq 0 ]; then
                echo -e "\rTransferring files to temp location... OK    "
                echo -n "Moving files to final destination (sudo required)... "
                
                # Move files with sudo
                sudo_cmd="sudo mkdir -p $(dirname "$destination") && sudo mv $temp_dir/* $destination/ && sudo rm -rf $temp_dir"
                (sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$username@$host" "$sudo_cmd" >> .transfer_log 2>&1) &
                pid=$!
                
                while kill -0 $pid 2>/dev/null; do
                    i=$(( (i+1) %4 ))
                    printf "\rMoving files to final destination (sudo required)... ${spin:$i:1}"
                    sleep 0.1
                done
                
                wait $pid
                scp_exit=$?
            fi
        else
            # Direct transfer
            (sshpass -p "$password" scp -P "$port" -o StrictHostKeyChecking=no -r $source_files "$username@$host:$destination" > .transfer_log 2>&1) &
            pid=$!
            
            while kill -0 $pid 2>/dev/null; do
                i=$(( (i+1) %4 ))
                printf "\rTransferring files... ${spin:$i:1}"
                sleep 0.1
            done
            
            wait $pid
            scp_exit=$?
        fi
        
        if [ $scp_exit -eq 0 ]; then
            echo -e "\rTransfer completed successfully!    "
        else
            echo -e "\rTransfer failed!                  "
            echo "=== Error Details ==="
            cat .transfer_log
            rm -f .transfer_log
            exit 1
        fi
        rm -f .transfer_log
    fi
}

# Function to run in GUI mode
gui_mode() {
    GUI_MODE=true
    
    # Check dependencies
    if ! command -v zenity &> /dev/null; then
        error_exit "zenity is required for GUI mode but not installed.\nPlease install with:\nsudo apt install zenity"
    fi
    if ! command -v sshpass &> /dev/null; then
        error_exit "sshpass is required but not installed.\nPlease install with:\nsudo apt install sshpass"
    fi

    # Get SSH credentials
    credentials=$(zenity --entry --title="SSH File Transfer" --text="Enter SSH credentials (user@host):" --width=300)
    [ -z "$credentials" ] && error_exit "Credentials are required!"

    # Validate credentials format
    if [[ ! "$credentials" =~ ^[^@]+@[^@]+$ ]]; then
        error_exit "Invalid format! Please use user@host format"
    fi

    username=${credentials%%@*}
    host=${credentials#*@}

    # Get password
    password=$(zenity --password --title="SSH Authentication" --text="Enter password for $credentials:")
    [ -z "$password" ] && error_exit "Password is required!"

    # Get SSH port with default 22
    port=$(zenity --entry --title="SSH Port" --text="Enter SSH port:" --entry-text="22")
    port=${port:-22}

    # Test SSH connection
    test_ssh_connection

    # Select files to transfer
    files=$(zenity --file-selection --title="Select Files/Directories to Transfer" --multiple --separator=" ")
    [ -z "$files" ] && error_exit "No files selected!"

    # Get destination path
    destination=$(zenity --entry --title="Destination Path" --text="Enter destination path on remote host:" --entry-text="/home/$username/")
    [ -z "$destination" ] && error_exit "Destination path is required!"

    # Check if destination requires sudo
    use_sudo=false
    if [[ "$destination" =~ ^/var/ || "$destination" =~ ^/etc/ || "$destination" =~ ^/usr/ || "$destination" =~ ^/root/ ]]; then
        zenity --question --title="Privileged Directory" --text="The destination directory appears to be system-protected.\n\nDo you need to use sudo to transfer files there?" --width=400
        [ $? -eq 0 ] && use_sudo=true
    fi

    # Confirm transfer
    zenity --question --title="Confirm Transfer" --text="Transfer $(echo $files | wc -w) item(s) to $host:$destination $( [ "$use_sudo" = true ] && echo "using sudo" )?" --width=300
    [ $? -ne 0 ] && exit 0

    # Perform transfer
    transfer_files "$files" "$destination" "$use_sudo"

    [ $? -eq 0 ] && zenity --info --text="Transfer completed successfully!" || exit 1
}

# Function to run in CLI mode
cli_mode() {
    GUI_MODE=false
    
    # Check dependencies
    if ! command -v sshpass &> /dev/null; then
        error_exit "sshpass is required but not installed.\nPlease install with:\nsudo apt install sshpass"
    fi

    # Get SSH credentials
    read -p "Enter SSH credentials (user@host): " credentials
    [ -z "$credentials" ] && error_exit "Credentials are required!"

    # Validate credentials format
    if [[ ! "$credentials" =~ ^[^@]+@[^@]+$ ]]; then
        error_exit "Invalid format! Please use user@host format"
    fi

    username=${credentials%%@*}
    host=${credentials#*@}

    # Get password securely
    read -s -p "Enter password for $credentials: " password
    echo
    [ -z "$password" ] && error_exit "Password is required!"

    # Get SSH port with default 22
    read -p "Enter SSH port [22]: " port
    port=${port:-22}

    # Test SSH connection with verbose output
    test_ssh_connection

    # Get files to transfer
    echo "Enter paths of files/directories to transfer (space-separated, use quotes for paths with spaces):"
    read -e -p "> " files
    [ -z "$files" ] && error_exit "No files specified!"

    # Get destination path
    read -p "Enter destination path on remote host [/home/$username/]: " destination
    destination=${destination:-"/home/$username/"}

    # Check if destination requires sudo
    use_sudo=false
    if [[ "$destination" =~ ^/var/ || "$destination" =~ ^/etc/ || "$destination" =~ ^/usr/ || "$destination" =~ ^/root/ ]]; then
        read -p "The destination appears to be system-protected. Use sudo for transfer? [y/N]: " sudo_choice
        [[ "$sudo_choice" =~ ^[Yy]$ ]] && use_sudo=true
    fi

    # Confirm transfer
    read -p "Transfer to $host:$destination $( [ "$use_sudo" = true ] && echo "using sudo" )? [y/N]: " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && exit 0

    # Perform transfer
    transfer_files "$files" "$destination" "$use_sudo"
}

# Main script
clear
echo "=== SSH File Transfer Script ==="
echo "=== Supports privileged directories with sudo ==="

# Check if running in terminal
if [ -t 0 ]; then
    # Interactive terminal - ask for mode
    PS3=$'\nSelect mode (1-2): '
    options=("GUI Mode (Graphical)" "CLI Mode (Command Line)")
    
    select opt in "${options[@]}"; do
        case $REPLY in
            1) gui_mode; break ;;
            2) cli_mode; break ;;
            *) echo "Invalid option. Please enter 1 or 2.";;
        esac
    done
else
    # Non-interactive (e.g., double-clicked) - default to GUI
    gui_mode
fi
