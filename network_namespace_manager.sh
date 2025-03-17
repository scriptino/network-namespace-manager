#!/bin/bash

LOG_FILE="/tmp/namespace_manager.log"
CONFIG_FILE="/tmp/namespace_config.txt"

# Check if the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run with superuser privileges (sudo)." >&2
  exit 1
fi

# Function to write message in a log file
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local caller_function="${FUNCNAME[1]}"
    
    # Write to a file all the informations (timestamp, level, caller function, messages)
    echo "[$timestamp] [$level] [$caller_function] $message" >> "$LOG_FILE"
    
    # Show only message in terminal
    echo "$message"
}

# Function to log the output and errors of called programs
exec_cmd() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local caller_function="${FUNCNAME[1]}"  # Function that called exec_cmd

    # Log the start of the command
    echo "[$timestamp] [INFO] [$caller_function] Executing command: $*" >> "$LOG_FILE"

    # Execute the command and capture output and exit code
    { 
        output=$("$@" 2>&1)
        exit_code=$?
        echo "[$timestamp] [INFO] [$caller_function] Output: $output" >> "$LOG_FILE"
    } || {
        echo "$output" >&2   # Show only errors in the terminal
    }

    # If the command fails, log it with the caller function name
    if [[ $exit_code -ne 0 ]]; then
        log_message "ERROR" "[$caller_function] Command '$*' failed with exit code $exit_code"
    fi

    return $exit_code
}

# Read IP addresses and gateway from the interface
read_interface() {
    # Try to get the IP address normally
    ip_address=$(ip addr show dev "$selected_interface" | grep 'inet ' | awk '{print $2}' | cut -d/ -f1 | sed -n '2p')

    # If no IP is found, try to extract it from `ip route`
    if [ -z "$ip_address" ]; then
        ip_address=$(ip route get 8.8.8.8 | awk '/src/ {print $7}')
    fi

    # Try to get the gateway normally
    gateway_ip=$(ip route | grep "default" | grep "$selected_interface" | awk '{print $3}' | head -n 1)

    # If no gateway is found, try to extract it from `ip route`
    if [ -z "$gateway_ip" ]; then
        gateway_ip=$(ip route get 8.8.8.8 | awk '/via/ {print $3}')
    fi

    if [ -z "$ip_address" ]; then
        log_message "ERROR" "Error: No IP address found for interface $selected_interface."
        return 1
    fi

    if [ -z "$gateway_ip" ]; then
        log_message "ERROR" "Error: No gateway found for interface $selected_interface."
        return 1
    fi
}

# Function to select the network interface
select_interface() {
    # Get only physical interfaces, excluding veth* and lo
#    interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -Ev '^veth|^lo'))
    interfaces=($(ip -o link show | awk -F': ' '{print $2}' | grep -Ev '^lo'))
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        log_message "ERROR" "No available interfaces."
        return 1
    fi
    log_message "INFO" "Available network interfaces:"
    for i in "${!interfaces[@]}"; do
        log_message "INFO" "$((i+1)). ${interfaces[$i]}"
    done
    read -p "Select a network interface (1-${#interfaces[@]}): " choice
    if [[ ! "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#interfaces[@]} )); then
        log_message "ERROR" "Invalid choice. Exiting."
        return 1
    fi
    selected_interface="${interfaces[$((choice-1))]}"
    read_interface  # Read IP address and gateway, store them in "ip_address" and "gateway_ip"
    if [ $? -ne 0 ]; then
        return 1
    fi

    ip3oct=$(echo "$ip_address" | cut -d'.' -f3)
    log_message "INFO" "You selected: $selected_interface with IP $ip_address and gateway $gateway_ip"  # ; third octet = $ip3oct"
}

# Function to select the namespace
select_namespace() {
    # Show available namespace
    log_message "INFO" "Available namespaces:"
    existing_namespaces=($(ip netns list | awk '{print $1}'))
    
    if [[ ${#existing_namespaces[@]} -eq 0 ]]; then
        log_message "WARNING" "No namespaces found."
    else
        for _ns in "${existing_namespaces[@]}"; do
            log_message "INFO" "- $_ns"
        done
    fi

    while true; do
        read -p "Enter the namespace name to run programs in: " namespace
        if [ -z "$namespace" ]; then
            log_message "ERROR" "Error: namespace name cannot be empty. Try again."
        else
            break  # Exit the loop if input is valid
        fi
    done

    if ! sudo ip netns list | grep -qw "$namespace"; then
        log_message "ERROR" "Error: namespace $namespace does not exist."
        return 1
    fi
}

select_user() {
    selected_user="$SUDO_USER"

    if [[ -z "$selected_user" ]]; then
        log_message "ERROR" "SUDO_USER is not set. Run the script with sudo."
        return 1
    fi

    log_message "INFO" "Using user: $selected_user"
}

# Function to choose between script output or program output
select_output() {
    read -p "Select terminal output, 0 = program ; 1 = script : " outp_
    # Check if the input is a number and either 0 or 1
    if [[ ! "$outp_" =~ ^[0-1]$ ]]; then
        log_message "ERROR" "Invalid choice."
        return 1
    fi
    log_message "INFO" "You selected: $outp_"
    return 0
}

# Create a custom file to use conky in the namespace
create_conky_config() {
    current_user="$SUDO_USER"
    local conky_config_dir="/home/$current_user/.config/conky/myns"
    conky_config_file="$conky_config_dir/$namespace.conf"

    # Create the directory if it doesn't exist
    exec_cmd mkdir -p "$conky_config_dir"

    # Create the Conky configuration file
    local conky_config=$(cat <<EOF
conky.config = {
    background = false,
    border_width = 0,
    cpu_avg_samples = 2,
    default_color = '#ffffff',
    default_outline_color = '#000000',
    default_shade_color = '#000000',
    font = 'DejaVuSans:size=9',
    double_buffer = true,
    draw_borders = false,
    draw_graph_borders = true,
    draw_outline = false,
    draw_shades = false,
    use_xft = true,
    gap_x = 12,
    gap_y = 50,
    minimum_width = 180,
    minimum_height = 170,
    net_avg_samples = 2,
    no_buffers = true,
    out_to_console = false,
    out_to_stderr = false,
    extra_newline = false,
    own_window = true,
    own_window_transparent = false,
    own_window_type = 'normal',
    update_interval = 1.0,
    uppercase = false,
    use_spacer = 'none',
    show_graph_scale = false,
    show_graph_range = false,
};

conky.text = [[
\${font DejaVuSans:style=bold:size=7}NETWORK \$hr
\${font}Net.Namespace: $namespace
\${font}Interface: $selected_interface
IP: \${addr $selected_interface}
\${downspeedgraph $selected_interface}
Down: \${downspeed $selected_interface}/s \$alignr \${totaldown $selected_interface}
\${upspeedgraph $selected_interface}
Up: \${upspeed $selected_interface}/s \$alignr \${totalup $selected_interface}
]];
EOF
)
    # Write the configuration file
    if ! echo "$conky_config" > "$conky_config_file"; then
        log_message "ERROR" "Error: unable to write configuration file $conky_config_file" >&2
        return 1
    fi

    log_message "INFO" "Created Conky configuration file for namespace $namespace: $conky_config_file"
    
    # Change file ownership to the normal user
    if ! sudo chown "$current_user":"$current_user" "$conky_config_file"; then
        log_message "ERROR" "Error: unable to change ownership of file $conky_config_file" >&2
        return 1
    fi

    # Modify file permissions (optional, if needed)
    if ! chmod 644 "$conky_config_file"; then
        log_message "ERROR" "Error: unable to modify permissions of file $conky_config_file" >&2
        return 1
    fi    
}

# Function to configure the namespace and network
create_namespace() {
    while true; do
        read -p "Enter a name for the namespace: " namespace
        if [[ "$namespace" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*$ ]]; then
            break  # Exit the loop if input is valid
        else
            log_message "ERROR" "Error: Invalid namespace name! Use letters, numbers, '-' or '_', but not only numbers."
        fi
    done
    
    free="free" # No use, only to avoid error in save/read operation to/from configuration file
    # Create the namespace (if it doesn't already exist)
    if ! sudo ip netns list | grep -qw "$namespace"; then
        # Configure the nameserver for the namespace
        exec_cmd sudo mkdir -p /etc/netns/$namespace
        echo "nameserver 8.8.8.8" | sudo tee /etc/netns/$namespace/resolv.conf > /dev/null
        log_message "INFO" "Created /etc/netns/$namespace/resolv.conf file for namespace $namespace"
        sleep 0.3
        # Create the namespace
        exec_cmd sudo ip netns add "$namespace"
        log_message "INFO" "Namespace $namespace created."
        # Save values to the temporary configuration file
      # echo "$namespace $selected_interface $ip3oct $ip_address $gateway_ip $free" | sudo tee -a "$CONFIG_FILE"
        echo "$namespace $selected_interface $ip3oct $ip_address $gateway_ip $free" >> "$CONFIG_FILE"
    else
        log_message "ERROR" "Namespace $namespace already exists."
    fi

    # Add the physical interface to the namespace
    exec_cmd sudo ip link set "$selected_interface" netns "$namespace"
    log_message "INFO" "Physical interface $selected_interface moved to namespace $namespace."

    # Configure the IP address for the physical interface in the namespace
    exec_cmd sudo ip netns exec "$namespace" ip addr add "$ip_address/24" dev "$selected_interface"
    exec_cmd sudo ip netns exec "$namespace" ip link set "$selected_interface" up

    # Configure the default route in the namespace
    exec_cmd sudo ip netns exec "$namespace" ip route add default via "$gateway_ip" dev "$selected_interface"
    log_message "INFO" "Default route configured: via $gateway_ip dev $selected_interface"
    log_message "INFO" "Configuration completed."

    # Create a custom Conky configuration file
    create_conky_config  
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Start a Conky instance in the namespace
    exec_cmd sudo ip netns exec "$namespace" sudo -u "$current_user" conky -c "$conky_config_file" > /dev/null 2>&1 &
    log_message "INFO" "Conky started in the namespace $namespace"
}

# Function to run a program in an existing namespace
run_programs_in_namespace() {
    # Keep asking until the user provides a valid choice
    while ! select_output; do
        log_message "ERROR" "Please try again with a valid choice."
    done

    read -p "Enter the program name to run: " program
    if ! command -v "$program" &>/dev/null; then
        log_message "ERROR" "Error: $program is not installed or not executable."
        return 1  # Return to the menu without executing anything
    fi

    log_message "INFO" "Starting $program in namespace $namespace as user $selected_user..."
    
    # If outp_ is 1, run the program in the background without output
    if [[ "$outp_" -eq 1 ]]; then
        sudo ip netns exec "$namespace" sudo -u "$selected_user" "$program" > /dev/null 2>&1 &
        log_message "INFO" "$program launched in the background."
    else
        read -p "Enter any program arguments (press Enter for none): " args
        sudo ip netns exec "$namespace" sudo -u "$selected_user" "$program" $args
    fi

    return 0  # Return to the menu
}

# Function to choose between deleting a single namespace or all namespaces
choose_one_all() {
    while true; do
        # Show available namespaces
        existing_namespaces=$(sudo ip netns list)
        if [[ -z "$existing_namespaces" ]]; then
            log_message "INFO" "No namespaces to delete."
            break  # Exit the loop and return to the menu
        fi
        log_message "INFO" "Currently available namespaces:"
        log_message "INFO" "$existing_namespaces"
        log_message "INFO" "Do you want to delete a single namespace or all?"
        log_message "INFO" "1) Single"
        log_message "INFO" "2) All"
        read -p "#? " choice

        case "$choice" in
            1)
                read -p "Enter the namespace name to delete (or press Enter to cancel): " ns
                [[ -z "$ns" ]] && break  # If the user presses Enter, exit the loop

                if sudo ip netns list | grep -qw "$ns"; then
                    delete_namespace "$ns"
                    if [ $? -ne 0 ]; then
                        return 1
                    fi
                else
                    log_message "ERROR" "Error: namespace '$ns' does not exist."
                fi
                ;;
            2)
                log_message "INFO" "Deleting all namespaces..."
                for ns in $(sudo ip netns list | awk '{print $1}'); do
                    delete_namespace "$ns"
                    if [ $? -ne 0 ]; then
                        return 1
                    fi
                    log_message "INFO" "Namespace '$ns' deleted successfully."
                done
                break  # After deleting all namespaces, exit the loop
                ;;
            *)
                log_message "ERROR" "Invalid choice."
                ;;
        esac
    done
}

# Close the Conky instance in the namespace and delete its configuration file
close_conky_and_delete_its_file() {
    current_user="$SUDO_USER"
    local conky_config_dir="/home/$current_user/.config/conky/myns"
    local conky_config_file="$conky_config_dir/$namespace.conf"

    # Terminate only the specific Conky instance(s)
    pids=$(sudo ip netns pids "$namespace" | xargs -I{} sudo ps -o pid,cmd -p {} | grep "conky -c $conky_config_file" | awk '{print $1}' | xargs)

    if [[ -n "$pids" ]]; then
        exec_cmd sudo kill $pids
        log_message "INFO" "Terminated Conky instance(s) ($pids) for namespace $namespace."
    else
        log_message "WARNING" "No running Conky instance found for namespace $namespace."
    fi

    # Wait to ensure processes are terminated
    sleep 1

    # Delete only the Conky configuration file for the specific namespace
    if [[ -f "$conky_config_file" ]]; then
        exec_cmd rm -f "$conky_config_file"
        log_message "INFO" "Deleted Conky configuration file for $namespace: $conky_config_file"
    else
        log_message "ERROR" "No Conky configuration file found for namespace $namespace."
    fi
}

# Read configuration from the temporary file
read_config() {
    # Retrieve information from the configuration file
    config_line=$(grep "^$namespace " "$CONFIG_FILE")
    if [ -z "$config_line" ]; then
        log_message "ERROR" "Error: configuration for namespace $namespace not found in the file."
        return 1
    fi

    # Extract information from the line containing the namespace
    selected_interface=$(echo "$config_line" | awk '{print $2}')
    ip3oct=$(echo "$config_line" | awk '{print $3}')
    ip_address=$(echo "$config_line" | awk '{print $4}')
    gateway_ip=$(echo "$config_line" | awk '{print $5}')
    free=$(echo "$config_line" | awk '{print $6}')

    return 0
}

# Function to delete a single namespace
delete_namespace() {
    local namespace="$1"  # The namespace name is passed as an argument

    if ! sudo ip netns list | grep -qw "$namespace"; then  
        log_message "ERROR" "Error: namespace $namespace does not exist."
        return 1  # Return 1 to signal an error to the caller
    fi

    if ! read_config; then
        return 1
    fi

    # Read data from a temporary file; retry for "max_attempts" times if reading fails
    max_attempts=5  # Maximum number of attempts
    attempt=0

    while [[ -z "$selected_interface" || -z "$ip3oct" || -z "$ip_address" || -z "$gateway_ip" || -z "$free" ]]; do
        ((attempt++))
        if (( attempt > max_attempts )); then
            log_message "ERROR" "Error: unable to read parameters from the configuration file after $max_attempts attempts."
            return 1
        fi

        log_message "INFO" "Attempt $attempt: re-reading parameters..."
    
        if ! read_config; then
            return 1
        fi

        sleep 0.5  # Small delay to avoid infinite loops in case of errors
    done

    log_message "INFO" "All parameters have been read successfully."

    # Call the function to close Conky and delete its configuration file
    close_conky_and_delete_its_file

    # Bring the physical interface back to the root namespace
    if ip netns exec "$namespace" ip link show "$selected_interface" &>/dev/null; then
        root_pid=$(pgrep -xo systemd)
        exec_cmd sudo ip netns exec "$namespace" ip link set "$selected_interface" netns $root_pid
        log_message "INFO" "Interface $selected_interface moved back to the root namespace."
    else
        log_message "ERROR" "Warning: interface $selected_interface is not present in namespace $namespace."
    fi

    # Restore the physical interface configuration: IP and gateway
    exec_cmd sudo ip link set dev "$selected_interface" up 
    sleep 1
    exec_cmd sudo ip addr add "$ip_address" dev "$selected_interface"
    sleep 1
    exec_cmd sudo ip route add default via "$gateway_ip" dev "$selected_interface"
    
    # Print for verification
    log_message "INFO" "Restored parameters for interface $selected_interface:"
    read_interface # Read IP and gateway from the selected physical interface, store values in ip_address and gateway_ip
    if [ $? -ne 0 ]; then
        return 1
    fi
    log_message "INFO" "IP Address: $ip_address"
    log_message "INFO" "Gateway IP: $gateway_ip"

    # Delete the namespace
    exec_cmd sudo ip netns delete "$namespace"
    log_message "INFO" "Namespace $namespace deleted."
    sleep 0.3
    exec_cmd sudo chattr -i /etc/netns/$ns/resolv.conf
    exec_cmd sudo rm -f /etc/netns/$ns/resolv.conf
    exec_cmd sudo rmdir /etc/netns/$ns

    # Remove the line from the configuration file
    exec_cmd sudo sed -i "/^$namespace /d" "$CONFIG_FILE"

    return 0  # Return 0 to indicate success
}

# Function to show available namespaces
show_namespace() {
    echo "=== Existing Network Namespaces and Interfaces ==="

    for ns_ in $(sudo ip netns list | awk '{print $1}'); do
        echo -n "Namespace: $ns_   Interfaces: "
        
        # Get interfaces with IP inside the namespace
        sudo ip netns exec "$ns_" ip -j addr show | jq -r '.[] | select(.ifname != "lo") | "- \(.ifname): \(.addr_info[0].local)/\(.addr_info[0].prefixlen)"'
        
        # Show the default route
        default_route=$(sudo ip netns exec "$ns_" ip route show default 2>/dev/null)
        if [[ -n "$default_route" ]]; then
            echo "Default Route: $default_route"
        else
            echo "Default Route: None"
        fi
        echo  # Empty line for separation
    done
}

# Display the menu
show_menu() {
    echo "====== MAIN MENU ======"
    echo "1) Show available namespaces"
    echo "2) Create a network namespace"
    echo "3) Run programs inside a namespace"
    echo "4) Delete namespaces"
    echo "5) Clear console"
    echo "6) Exit"
    read -p "Choice: " choice
}

# Clear the screen and start the main loop
clear
while true; do
    show_menu
    case "$choice" in
        1)
            clear
            show_namespace
            ;;
        2)
            log_message "INFO" "Starting configuration..."
            select_interface
            if [[ $? -ne 0 ]]; then
                log_message "ERROR" "An error occurred while selecting the interface."
                continue
            fi
            create_namespace
            if [[ $? -ne 0 ]]; then
                log_message "ERROR" "An error occurred while creating the namespace."
                continue
            fi
            ;;
        3)
            # log_message "INFO" "Running the program..."
            select_namespace
            if [[ $? -ne 0 ]]; then
                log_message "ERROR" "An error occurred while selecting the namespace."
                continue
            fi
            select_user
            if [[ $? -ne 0 ]]; then
                log_message "ERROR" "An error occurred while selecting the user."
                continue
            fi
            run_programs_in_namespace
            if [[ $? -ne 0 ]]; then
                log_message "ERROR" "An error occurred while running the program in the namespace."
                continue
            fi
            ;;
        4)
            log_message "INFO" "Deleting namespace(s)..."
            choose_one_all  # Allows deletion of one or more namespaces
            if [[ $? -ne 0 ]]; then
                log_message "ERROR" "An error occurred while deleting one or more namespaces."
                continue
            fi
            ;;
        5)
            clear  # Clear screen
            continue
            ;;
        6)
            log_message "INFO" "Exiting."
            exit 0
            ;;
        *)
            log_message "ERROR" "Invalid choice, please try again."
            sleep 1
            ;;
    esac
    echo -e "\nPress ENTER to return to the main menu..."
    read
done
