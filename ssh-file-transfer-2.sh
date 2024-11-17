#!/bin/bash

# Set the GTK theme to dark
export GTK_THEME=Greybird-Dark:dark

# File to store SSH credentials (existing file)
credential_file="/home/x/Desktop/txt.and.sh/BASH-SCRIPTS/ssh-tmp/ssh-id.txt"

# Function to save a [TRANSFER] entry (only user@ip and -p port)
save_transfer() {
  local user_ip="$1"
  local port="$2"
  echo "$user_ip -p $port" >> "$credential_file"
}

# Function to display the previous transfers in the correct format
select_saved_ssh_id() {
  if [ ! -s "$credential_file" ]; then
    zenity --error --text="No saved SSH transfers found!"
    return 1
  fi

  # Read and format the entries in the format 'user@ip -p port'
  entries=$(awk '{print $1 " -p " $3}' "$credential_file" | sort -u)

  # Combine the entries with a prompt for "Use ID" and "Create New Transfer" buttons
  selected_id=$(zenity --list --title="SSH File Transfer" --text="Select an action:" \
    --column="Previous Transfers" $entries \
    --ok-label="Use Saved Transfer ID" \
    --cancel-label="Create New Transfer" \
    --extra-button="Exit" 2>/dev/null)

  echo "$selected_id"
}

# Function to execute the transfer
execute_transfer() {
  local user_ip="$1"
  local port="$2"
  local password="$3"
  local file="$4"
  local target_path="$5"

  # Show progress while transferring
  (
    sshpass -p "$password" scp -P "$port" "$file" "$user_ip:$target_path" &
    transfer_pid=$!
    while ps | grep -q "[s]cp "; do
      sleep 1
    done
  ) | zenity --progress --title="File Transfer" --text="Transferring to $user_ip -p $port..." --percentage=0 --pulsate

  # Save the transfer regardless of success
  save_transfer "$user_ip" "$port"

  wait $transfer_pid
  if [ $? -eq 0 ]; then
    zenity --info --text="File transfer successful!"
  else
    zenity --error --text="File transfer failed!"
  fi
}

# Main Loop
while true; do
  # Main window where user selects an action
  action=$(select_saved_ssh_id)

  if [ "$action" == "Exit" ]; then
    exit 0
  fi

  case "$action" in
    "Create New Transfer")
      user_ip=$(zenity --entry --title="SSH File Transfer" --text="Enter the SSH credentials (e.g., user@ip-address):")
      if [ $? -ne 0 ]; then exit 0; fi

      port=$(zenity --entry --title="SSH File Transfer" --text="Enter the SSH Port (default: 22):" --entry-text="22")
      if [ $? -ne 0 ]; then exit 0; fi
      port=${port:-22}

      password=$(zenity --password --title="SSH Password" --text="Enter the SSH password for $user_ip:")
      if [ $? -ne 0 ]; then exit 0; fi

      file=$(zenity --file-selection --title="Select File or Directory for Transfer")
      if [ $? -ne 0 ]; then exit 0; fi

      target_path=$(zenity --entry --title="SSH File Transfer" --text="Enter the destination path on the SSH client (e.g., /home/username/):")
      if [ $? -ne 0 ]; then exit 0; fi

      execute_transfer "$user_ip" "$port" "$password" "$file" "$target_path"
      ;;
    
    "Use Saved Transfer ID")
      # Extract user and port from the selected entry
      user_ip=$(echo "$action" | awk '{print $1}' | cut -d'@' -f1)
      port=$(echo "$action" | awk '{print $2}' | cut -d' ' -f2)

      password=$(zenity --password --title="SSH Password" --text="Enter the SSH password for $user_ip:")
      if [ $? -ne 0 ]; then continue; fi

      file=$(zenity --file-selection --title="Select File or Directory for Transfer")
      if [ $? -ne 0 ]; then exit 0; fi

      target_path=$(zenity --entry --title="SSH File Transfer" --text="Enter the destination path on the SSH client (e.g., /home/username/):")
      if [ $? -ne 0 ]; then exit 0; fi

      execute_transfer "$user_ip" "$port" "$password" "$file" "$target_path"
      ;;
  esac
done
