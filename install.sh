#!/bin/bash

# Detect OS and set package/service managers
if [ -f /etc/redhat-release ]; then
    if grep -q "Rocky" /etc/redhat-release; then
        OS="Rocky"
        PACKAGE_MANAGER="dnf"
        SERVICE_MANAGER="systemctl"
    elif grep -q "AlmaLinux" /etc/redhat-release; then
        OS="AlmaLinux"
        PACKAGE_MANAGER="dnf"
        SERVICE_MANAGER="systemctl"
    else
        OS="CentOS"
        PACKAGE_MANAGER="yum"
        SERVICE_MANAGER="systemctl"
    fi
elif [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
        ubuntu)
            OS="Ubuntu"
            PACKAGE_MANAGER="apt"
            SERVICE_MANAGER="systemctl"
            ;;
        debian)
            OS="Debian"
            PACKAGE_MANAGER="apt"
            SERVICE_MANAGER="systemctl"
            ;;
        fedora)
            OS="Fedora"
            PACKAGE_MANAGER="dnf"
            SERVICE_MANAGER="systemctl"
            ;;
        *)
            echo "Unsupported OS"
            exit 1
            ;;
    esac
else
    echo "Unsupported OS"
    exit 1
fi

# Update and Upgrade Server
if [ "$PACKAGE_MANAGER" = "apt" ]; then
    sudo apt update && sudo apt upgrade -y
else
    sudo $PACKAGE_MANAGER update -y
fi

# Install necessary packages
install_package() {
    package=$1
    if ! command -v $package &> /dev/null; then
        echo "Installing $package..."
        sudo $PACKAGE_MANAGER install $package -y > /dev/null
    fi
}

install_package dialog
install_package whiptail
install_package jq
install_package lsof
install_package tar 
install_package wget
clear


# Define partial functions
##############################
## Functions for iptables setup
install_iptables() {
    IP=$(whiptail --inputbox "Enter your main server IP like (1.1.1.1):" 8 60 3>&1 1>&2 2>&3)
    TCP_PORTS=$(whiptail --inputbox "Enter ports separated by commas (e.g., 80,443):" 8 60 80,443 3>&1 1>&2 2>&3)

    {
        echo "10" "Installing iptables..."
        sudo $PACKAGE_MANAGER install iptables -y > /dev/null 2>&1
        echo "30" "Enabling net.ipv4.ip_forward..."
        sudo sysctl net.ipv4.ip_forward=1 > /dev/null 2>&1
        echo "50" "Configuring iptables rules for TCP..."
        sudo iptables -t nat -A POSTROUTING -p tcp --match multiport --dports $TCP_PORTS -j MASQUERADE > /dev/null 2>&1
        echo "60" "Configuring iptables rules for TCP DNAT..."
        sudo iptables -t nat -A PREROUTING -p tcp --match multiport --dports $TCP_PORTS -j DNAT --to-destination $IP > /dev/null 2>&1
        echo "75" "Configuring iptables rules for UDP..."
        sudo iptables -t nat -A POSTROUTING -p udp --match multiport --dports $TCP_PORTS -j MASQUERADE > /dev/null 2>&1
        echo "85" "Configuring iptables rules for UDP DNAT..."
        sudo iptables -t nat -A PREROUTING -p udp --match multiport --dports $TCP_PORTS -j DNAT --to-destination $IP > /dev/null 2>&1
        echo "95" "Creating /etc/iptables/..."
        sudo mkdir -p /etc/iptables/ > /dev/null 2>&1
        sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null
        echo "100" "Starting iptables service..."
        sudo systemctl start iptables
    } | dialog --title "IPTables Installation" --gauge "Installing IPTables..." 10 100 0
    clear
    whiptail --title "IPTables Installation" --msgbox "IPTables installation completed." 8 60
}

check_port_iptables() {
    ip_ports=$(iptables-save | awk '/-A (PREROUTING|POSTROUTING)/ && /-p tcp -m multiport --dports/ {split($0, parts, "--to-destination "); split(parts[2], dest_port, "[:]"); split(parts[1], src_port, " --dports "); split(src_port[2], port_list, ","); for (i in port_list) { if(dest_port[1] != "") { if (index(port_list[i], " ")) { split(port_list[i], split_port, " "); print dest_port[1], split_port[1] } else print dest_port[1], port_list[i] }}}'
)
    status=$(sudo systemctl is-active iptables)
    service_status="iptables Service Status: $status"
    info="Service Status and Ports in Use:\n$ip_ports\n\n$service_status"
    whiptail --title "iptables Service Status and Ports" --msgbox "$info" 15 70
}

uninstall_iptables() {
    {
        echo "10" "Flushing iptables rules..."
        sudo iptables -F > /dev/null 2>&1
        sleep 1
        echo "20" "Deleting all user-defined chains..."
        sudo iptables -X > /dev/null 2>&1
        sleep 1
        echo "40" "Flushing NAT table..."
        sudo iptables -t nat -F > /dev/null 2>&1
        sleep 1
        echo "50" "Deleting user-defined chains in NAT table..."
        sudo iptables -t nat -X > /dev/null 2>&1
        sleep 1
        echo "70" "Removing /etc/iptables/rules.v4..."
        sudo rm /etc/iptables/rules.v4 > /dev/null 2>&1
        sleep 1
        echo "80" "Stopping iptables service..."
        sudo systemctl stop iptables > /dev/null 2>&1
        sleep 1
        echo "100" "IPTables Uninstallation completed!"
    } | dialog --title "IPTables Uninstallation" --gauge "Uninstalling IPTables..." 10 100 0
    clear
    whiptail --title "IPTables Uninstallation" --msgbox "IPTables Uninstalled." 8 60
}


##########################
## Functions for GOST setup
install_gost() {
    {
        echo "10"
        curl -fsSL https://github.com/go-gost/gost/raw/master/install.sh | bash -s -- --install > /dev/null 2>&1
        echo "50"
        sudo wget -q -O /usr/lib/systemd/system/gost.service https://raw.githubusercontent.com/ipmartnetwork/multitunnel/main/gost.service > /dev/null 2>&1
        sleep 1
        echo "70"
    } | dialog --title "GOST Installation" --gauge "Installing GOST..." 10 60

    domain=$(whiptail --inputbox "Enter your domain or IP:" 8 60 --title "GOST Installation" 3>&1 1>&2 2>&3)
    while : ; do
        port=$(whiptail --inputbox "Enter the port number (1-65535):" 8 60 --title "Port Input" 3>&1 1>&2 2>&3)
        if [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]]; then
            break
        else
            whiptail --title "Invalid Input" --msgbox "Port must be a numeric value between 1 and 65535. Please try again." 8 60
        fi
    done

    {
        echo "80"
        sudo sed -i "s|ExecStart=/usr/local/bin/gost -L=tcp://:\$port/\$domain:\$port|ExecStart=/usr/local/bin/gost -L=tcp://:$port/$domain:$port|g" /usr/lib/systemd/system/gost.service > /dev/null 2>&1
        sudo systemctl daemon-reload > /dev/null 2>&1
        sudo systemctl start gost > /dev/null 2>&1
        sudo systemctl enable gost > /dev/null 2>&1
        echo "100"
        sleep 1
    } | dialog --title "GOST Configuration" --gauge "Configuring GOST service..." 10 60

    status=$(sudo systemctl is-active gost)

    if [ "$status" = "active" ]; then
        whiptail --title "GOST Service Status" --msgbox "GOST tunnel is installed and active." 8 60
    else
        whiptail --title "GOST Installation" --msgbox "GOST service is not active. Status: $status." 8 60
    fi
    clear
}

check_port_gost() {
    gost_ports=$(sudo lsof -i -P -n -sTCP:LISTEN | grep gost | awk '{print $9}')
    status=$(sudo systemctl is-active gost)
    service_status="gost Service Status: $status"
    info="Service Status and Ports in Use:\n\nPorts in use:\n$gost_ports\n\n$service_status"
    whiptail --title "gost Service Status and Ports" --msgbox "$info" 15 70
}

add_port_gost() {
    last_port=$(sudo lsof -i -P -n -sTCP:LISTEN | grep gost | awk '{print $9}' | awk -F ':' '{print $NF}' | sort -n | tail -n 1)

    new_domain=$(whiptail --inputbox "Enter your domain or IP:" 8 60  --title "GOST Installation" 3>&1 1>&2 2>&3)

    while : ; do
        new_port=$(whiptail --inputbox "Enter the port (numeric only):" 8 60 --title "Port Input" 3>&1 1>&2 2>&3)
        
        if [[ "$new_port" =~ ^[0-9]+$ ]]; then
            if (( new_port >= 0 && new_port <= 65535 )); then
                if sudo lsof -i -P -n -sTCP:LISTEN | grep ":$new_port " > /dev/null 2>&1; then
                    whiptail --title "Port Already in Use" --msgbox "Port $new_port is already in use. Please choose another port." 8 60
                else
                    break
                fi
            else
                whiptail --title "Invalid Port Number" --msgbox "Port number must be between 1 and 65535. Please try again." 8 60
            fi
        else
            whiptail --title "Invalid Input" --msgbox "Port must be a numeric value. Please try again." 8 60
        fi
    done

    sudo sed -i "/ExecStart/s/$/ -L=tcp:\/\/:$new_port\/$new_domain:$new_port/" /usr/lib/systemd/system/gost.service > /dev/null 2>&1
    sudo systemctl daemon-reload > /dev/null 2>&1
    sudo systemctl restart gost > /dev/null 2>&1
    whiptail --title "GOST configuration" --msgbox "New domain and port added." 8 60
}

remove_port_gost() {
    ports=$(grep -oP '(?<=-L=tcp://:)\d+(?=/)' /usr/lib/systemd/system/gost.service)

    if [ -z "$ports" ]; then
        whiptail --title "Remove Port" --msgbox "No ports found in the GOST configuration." 8 60
        return
    fi

    port_list=()
    for port in $ports; do
        port_list+=("$port" "")
    done

    selected_port=$(whiptail --title "Remove Port" --menu "Choose the port to remove:" 15 60 5 "${port_list[@]}" 3>&1 1>&2 2>&3)

    if [ -z "$selected_port" ]; then
        whiptail --title "Remove Port" --msgbox "No port selected. No changes made." 8 60
        return
    fi

    line=$(grep -oP "ExecStart=.*-L=tcp://:$selected_port/[^ ]+" /usr/lib/systemd/system/gost.service)
    domain=$(echo "$line" | grep -oP "(?<=-L=tcp://:$selected_port/).+")

    if (whiptail --title "Confirm Removal" --yesno "Are you sure you want to remove the port $selected_port with domain/IP $domain?" 8 60); then
        sudo sed -i "\|ExecStart=.*-L=tcp://:$selected_port/$domain|s| -L=tcp://:$selected_port/$domain||" /usr/lib/systemd/system/gost.service

        {
            echo "50"
            sudo systemctl daemon-reload > /dev/null 2>&1
            sudo systemctl restart gost > /dev/null 2>&1
            echo "100"
        } | dialog --title "GOST Configuration" --gauge "Removing port $selected_port from GOST service..." 10 60

        whiptail --title "Remove Port" --msgbox "Port $selected_port with domain/IP $domain has been removed from the GOST configuration." 8 60
    else
        whiptail --title "Remove Port" --msgbox "No changes made." 8 60
    fi
}

uninstall_gost() {
    {
        echo "20" "Stopping GOST service..."
        sudo systemctl stop gost > /dev/null 2>&1
        sleep 1
        echo "40" "Disabling GOST service..."
        sudo systemctl disable gost > /dev/null 2>&1
        sleep 1
        echo "60" "Reloading systemctl daemon..."
        sudo systemctl daemon-reload > /dev/null 2>&1
        sleep 1
        echo "80" "Removing GOST service and binary..."
        sudo rm -f /usr/lib/systemd/system/gost.service /usr/local/bin/gost
        sleep 1
    } | dialog --title "GOST Uninstallation" --gauge "Uninstalling GOST..." 10 60 0
    clear
    whiptail --title "GOST Uninstallation" --msgbox "GOST Service Uninstalled." 8 60
}

##########################
## Functions for Xray setup
install_xray() {
    sudo bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>&1 | dialog --title "Xray Installation" --progressbox 30 120

    whiptail --title "Xray Installation" --msgbox "Xray installation completed!" 8 60
    clear
    address=$(whiptail --inputbox "Enter your domain or IP:" 8 60 --title "Address Input" 3>&1 1>&2 2>&3)
    while : ; do
        port=$(whiptail --inputbox "Enter the port (numeric only 1-65535):" 8 60 --title "Port Input" 3>&1 1>&2 2>&3)
        if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
            break
        else
            whiptail --title "Invalid Input" --msgbox "Port must be a numeric value between 1 and 65535. Please try again." 8 60
        fi
    done
    wget -O /tmp/config.json https://raw.githubusercontent.com/ipmartnetwork/multitunnel/main/config.json > /dev/null 2>&1
    clear
    jq --arg address "$address" --arg port "$port" '.inbounds[1].port = ($port | tonumber) | .inbounds[1].settings.address = $address | .inbounds[1].settings.port = ($port | tonumber) | .inbounds[1].tag = "inbound-" + $port' /tmp/config.json > /usr/local/etc/xray/config.json

    sudo systemctl restart xray
    status=$(sudo systemctl is-active xray)

    if [ "$status" = "active" ]; then
        whiptail --title "Install Xray" --msgbox "Xray installed successfully!" 8 60
    else
        whiptail --title "Install Xray" --msgbox "Xray service is not active or failed." 8 60
    fi

    rm /tmp/config.json
}

check_service_xray() {
    xray_ports=$(sudo lsof -i -P -n -sTCP:LISTEN | grep xray | awk '{print $9}')

    status=$(sudo systemctl is-active xray)
    service_status="Xray Service Status: $status"

    info="Service Status and Ports in Use:\n\nPorts in use:\n$xray_ports\n\n$service_status"

    whiptail --title "Xray Service Status and Ports" --msgbox "$info" 15 70

}

add_another_inbound() {
    addressnew=$(whiptail --inputbox "Enter the new address:" 8 60 --title "Address Input" 3>&1 1>&2 2>&3)

    while : ; do
        portnew=$(whiptail --inputbox "Enter the new port (numeric only):" 8 60 --title "Port Input" 3>&1 1>&2 2>&3)
        
        if ! [[ "$portnew" =~ ^[0-9]+$ ]]; then
            whiptail --title "Invalid Input" --msgbox "Port must be a numeric value. Please try again." 8 60
            continue
        fi

        if jq --arg port "$portnew" '.inbounds[] | select(.port == ($port | tonumber))' /usr/local/etc/xray/config.json | grep -q .; then
            whiptail --title "Port In Use" --msgbox "The port $portnew is already in use. Please enter a different port." 8 60
        else
            break
        fi
    done

    if jq --arg address "$addressnew" --arg port "$portnew" '.inbounds += [{ "listen": null, "port": ($port | tonumber), "protocol": "dokodemo-door", "settings": { "address": $address, "followRedirect": false, "network": "tcp,udp", "port": ($port | tonumber) }, "tag": ("inbound-" + $port) }]' /usr/local/etc/xray/config.json > /tmp/config.json.tmp; then
        sudo mv /tmp/config.json.tmp /usr/local/etc/xray/config.json
        sudo systemctl restart xray
        whiptail --title "Install Xray" --msgbox "Additional inbound added." 8 60
    else
        whiptail --title "Install Xray" --msgbox "Error: Failed to add inbound configuration." 8 60
    fi
}

remove_inbound() {
    inbounds=$(jq -r '.inbounds[] | select(.tag != "api") | "\(.tag):\(.port)"' /usr/local/etc/xray/config.json)
    
    if [ -z "$inbounds" ]; then
        whiptail --title "Remove Inbound" --msgbox "No inbound configurations found." 8 60
        return
    fi
    
    selected=$(whiptail --title "Remove Inbound" --menu "Select the inbound configuration to remove:" 20 60 10 \
    $(echo "$inbounds" | awk -F ':' '{print $1}' | nl -w2 -s ' ') 3>&1 1>&2 2>&3)

    if [ -n "$selected" ]; then
        port=$(echo "$inbounds" | sed -n "${selected}p" | awk -F ':' '{print $2}')
        
        # Confirm removal
        whiptail --title "Confirm Removal" --yesno "Are you sure you want to remove the inbound configuration for port $port?" 8 60
        response=$?
        if [ $response -eq 0 ]; then
            remove_inbound_by_port "$port"
        else
            whiptail --title "Remove Inbound" --msgbox "Inbound configuration removal canceled." 8 60
        fi
    fi
}

remove_inbound_by_port() {
    port=$1
    if jq --arg port "$port" 'del(.inbounds[] | select(.port == ($port | tonumber)))' /usr/local/etc/xray/config.json > /tmp/config.json.tmp; then
        sudo mv /tmp/config.json.tmp /usr/local/etc/xray/config.json
        sudo systemctl restart xray
        if grep -q "\"port\": $port" /usr/local/etc/xray/config.json; then
            whiptail --title "Remove Inbound" --msgbox "Failed to remove inbound configuration." 8 60
        else
            whiptail --title "Remove Inbound" --msgbox "Inbound configuration removed successfully!" 8 60
        fi
    else
        whiptail --title "Remove Inbound" --msgbox "Failed to remove inbound configuration." 8 60
    fi
}

uninstall_xray() {
    (
    echo "10" "Removing Xray configuration..."
    sudo rm /usr/local/etc/xray/config.json > /dev/null 2>&1
    sleep 1
    echo "30" "Stopping and disabling Xray service..."
    sudo systemctl stop xray && sudo systemctl disable xray > /dev/null 2>&1
    sleep 1
    echo "70" "Uninstalling Xray..."
    sudo bash -c "$(curl -sL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove > /dev/null 2>&1
    sleep 1
    echo "100" "Xray Uninstallation completed!"
    sleep 1
    ) | dialog --title "Xray Uninstallation" --gauge "Xray Uninstallation in progress..." 10 100 0
    whiptail --title "Xray Uninstallation" --msgbox "Xray Uninstallation completed!" 8 60
    clear
}

##############################
## Functions for HA-Proxy setup
install_haproxy() {
    {
        echo "10" "Installing HAProxy..."
        sudo $PACKAGE_MANAGER install haproxy -y > /dev/null 2>&1
        sleep 1
        echo "30" "Downloading haproxy.cfg..."
        wget -q -O /tmp/haproxy.cfg "https://raw.githubusercontent.com/ipmartnetwork/multitunnel/main/haproxy.cfg" > /dev/null 2>&1
        sleep 1
        echo "50" "Removing existing haproxy.cfg..."
        sudo rm /etc/haproxy/haproxy.cfg > /dev/null 2>&1
        sleep 1
        echo "70" "Moving new haproxy.cfg to /etc/haproxy..."
        sudo mv /tmp/haproxy.cfg /etc/haproxy/haproxy.cfg
        sleep 1
    } | dialog --title "HAProxy Installation" --gauge "Installing HAProxy..." 10 60 0

    whiptail --title "HAProxy Installation" --msgbox "HAProxy installation completed." 8 60

    while true; do
        target_iport=$(whiptail --inputbox "Enter Relay-Server Free Port (1-65535):" 8 60 --title "HAProxy Installation" 3>&1 1>&2 2>&3)
        if [[ "$target_iport" =~ ^[0-9]+$ ]] && [ "$target_iport" -ge 1 ] && [ "$target_iport" -le 65535 ]; then
            break
        else
            whiptail --title "Invalid Input" --msgbox "Please enter a valid numeric port between 1 and 65535." 8 60
        fi
    done

    target_ip=$(whiptail --inputbox "Enter Main-Server IP:" 8 60 --title "HAProxy Installation" 3>&1 1>&2 2>&3)

    while true; do
        target_port=$(whiptail --inputbox "Enter Main-Server Port (1-65535):" 8 60 --title "HAProxy Installation" 3>&1 1>&2 2>&3)
        if [[ "$target_port" =~ ^[0-9]+$ ]] && [ "$target_port" -ge 1 ] && [ "$target_port" -le 65535 ]; then
            break
        else
            whiptail --title "Invalid Input" --msgbox "Please enter a valid numeric port between 1 and 65535." 8 60
        fi
    done

    if [[ -n "$target_ip" ]]; then
        sudo sed -i "s/\$iport/$target_iport/g; s/\$IP/$target_ip/g; s/\$port/$target_port/g" /etc/haproxy/haproxy.cfg > /dev/null 2>&1
        sudo systemctl restart haproxy > /dev/null 2>&1

        status=$(sudo systemctl is-active haproxy)
        if [ "$status" = "active" ]; then
            whiptail --title "HAProxy Installation" --msgbox "HA-Proxy tunnel is installed and active." 8 60
        else
            whiptail --title "HAProxy Installation" --msgbox "HA-Proxy service is not active. Status: $status." 8 60
        fi
    else
        whiptail --title "HAProxy Installation" --msgbox "Invalid IP input. Please ensure the field is filled correctly." 8 60
    fi
}

check_haproxy() {
    haproxy_ports=$(sudo lsof -i -P -n -sTCP:LISTEN | grep haproxy | awk '{print $9}')
    status=$(sudo systemctl is-active haproxy)
    service_status="haproxy Service Status: $status"
    info="Service Status and Ports in Use:\n\nPorts in use:\n$haproxy_ports\n\n$service_status"
    whiptail --title "haproxy Service Status and Ports" --msgbox "$info" 15 70
}

uninstall_haproxy() {
    {
        echo "20" "Stopping HAProxy service..."
        sudo systemctl stop haproxy > /dev/null 2>&1
        sleep 1
        echo "40" "Disabling HAProxy service..."
        sudo systemctl disable haproxy > /dev/null 2>&1
        sleep 1
        echo "60" "Removing HAProxy..."
        sudo $PACKAGE_MANAGER remove haproxy -y > /dev/null 2>&1
        sleep 1
    } | dialog --title "HAProxy Uninstallation" --gauge "Uninstalling HAProxy..." 10 60 0

    whiptail --title "HAProxy Uninstallation" --msgbox "HA-Proxy Uninstalled." 8 60
    clear
}

##############################
## Functions for Options setup
function configure_dns() {
    sudo rm /etc/resolv.conf > /dev/null 2>&1

    dns1=$(whiptail --inputbox "Enter DNS Server 1(like 8.8.8.8):" 8 60 3>&1 1>&2 2>&3)
    dns2=$(whiptail --inputbox "Enter DNS Server 2(like 8.8.4.4):" 8 60 3>&1 1>&2 2>&3)

    echo "nameserver $dns1" | sudo tee -a /etc/resolv.conf
    echo "nameserver $dns2" | sudo tee -a /etc/resolv.conf

    whiptail --title "DNS Configuration" --msgbox "DNS Configuration completed." 8 60
    clear
}

function update_server() {
    (
        sudo $PACKAGE_MANAGER update -y
        echo "100" "Update completed."
    ) | dialog --title "Update Server" --progressbox 30 120

    whiptail --title "Update Server" --msgbox "Server Update completed." 8 60
    clear
}

function ping_websites() {
    websites=("github.com" "google.com" "www.cloudflare.com")
    results_file=$(mktemp)

    for website in "${websites[@]}"; do
        gauge_title="Pinging $website"
        gauge_percentage=0
        success=false

        (
            for _ in {1..5}; do
                sleep 1  
                ((gauge_percentage += 20))
                echo "$gauge_percentage"
                echo "# $gauge_title"
                echo "Pinging $website..."
                
                if ping -c 1 $website &> /dev/null; then
                    success=true
                fi
            done
            echo "100" 
        ) | dialog --title "Ping $website" --gauge "$gauge_title" 10 80 0

        result=$(ping -c 5 $website | tail -n 2)
        echo -e "\n\nPing results for $website:\n$result" >> "$results_file"
    done

    whiptail --title "Ping Websites" --textbox "$results_file" 30 80
    clear

    rm "$results_file"
}


################################################################
# Define the functions to be executed when an option is selected

# Graphical functionality for IP-Tables menu
iptables_menu() {
    while true; do
        choice=$(whiptail --backtitle "Multi Tunnel" --title "IP-Tables Menu" --menu "Please choose one of the following options:" 20 60 10 \
        "Install" "Install IP-Tables Rules" \
        "Status" "Check Ports In Use" \
        "Uninstall" "Uninstall IP-Tables Rules" \
        "Back" "Back To Main Menu" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $choice in
                Install)
                    install_iptables
                    ;;
                Status)
                    check_port_iptables
                    ;;
                Uninstall)
                    uninstall_iptables
                    ;;
                Back)
                    menu
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    exit 1
                    ;;
            esac
        else
            exit 1
        fi
    done
}

# Graphical functionality for GOST menu
gost_menu() {
    while true; do
        choice=$(whiptail --backtitle "Multi Tunnel" --title "GOST Menu" --menu "Please choose one of the following options:" 20 60 10 \
        "Install" "Install GOST" \
        "Status" "Check GOST Port And Status" \
        "Add" "Add Another Port And Domain" \
        "Remove" "Remove Port And Domain" \
        "Uninstall" "Uninstall GOST" \
        "Back" "Back To Main Menu" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $choice in
                Install)
                    install_gost
                    ;;
                Status)
                    check_port_gost
                    ;;
                Add)
                    add_port_gost
                    ;;
                Remove)
                    remove_port_gost
                    ;;
                Uninstall)
                    uninstall_gost
                    ;;
                Back)
                    menu
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    exit 1
                    ;;
            esac
        else
            exit 1
        fi
    done
}

dokodemo_menu() {
    while true; do
        choice=$(whiptail --backtitle "Multi Tunnel" --title "Dokodemo-Door Menu" --menu "Please choose one of the following options:" 20 60 10 \
        "Install" "Install Xray For Dokodemo-Door And Add Inbound" \
        "Status" "Check Xray Service Status" \
        "Add" "Add Another Inbound" \
        "Remove" "Remove an Inbound Configuration" \
        "Uninstall" "Uninstall Xray And Tunnel" \
        "Back" "Back To Main Menu" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $choice in
                Install)
                    install_xray
                    ;;
                Status)
                    check_service_xray
                    ;;
                Add)
                    add_another_inbound
                    ;;
                Remove)
                    remove_inbound
                    ;;
                Uninstall)
                    uninstall_xray
                    ;;
                Back)
                    menu
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    exit 1
                    ;;
            esac
        else
            exit 1
        fi
    done
}


# Graphical functionality for Socat menu
haproxy_menu() {
    while true; do
        choice=$(whiptail --backtitle "Multi Tunnel" --title "HA-Proxy Menu" --menu "Please choose one of the following options:" 20 60 10 \
        "Install" "Install HA-Proxy" \
        "Status" "Check HA-Proxy Port and Status" \
        "Uninstall" "Uninstall HAProxy" \
        "Back" "Back To Main Menu" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $choice in
                Install)
                    install_haproxy
                    ;;
                Status)
                    check_haproxy
                    ;;
                Uninstall)
                    uninstall_haproxy
                    ;;
                Back)
                    menu
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    exit 1
                    ;;
            esac
        else
            exit 1
        fi
    done
}

# Define the submenu for Other Options
function other_options_menu() {
    while true; do
        other_choice=$(whiptail --backtitle "Welcome to iPmart Multi Tunnel" --title "Other Options" --menu "Please choose one of the following options:" 20 60 10 \
        "DNS" "Configure DNS" \
        "Update" "Update Server" \
        "Ping" "Ping to check internet connectivity" \
        "Back" "Return to Main Menu" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $other_choice in
                DNS)
                    configure_dns
                    ;;
                Update)
                    update_server
                    ;;
                Ping)
                    ping_websites
                    ;;
                Back)
                    menu
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    ;;
            esac
        else
            exit 1
        fi
    done
}
#################################
# Define the main graphical menu
function menu() {
    while true; do
        choice=$(whiptail --backtitle "Welcome to iPmart Multi Tunnel" --title "Choose Your Tunnel Mode" --menu "Please choose one of the following options:" 20 60 10 \
        "IP-Tables" "Manage IP-Tables Tunnel" \
        "GOST" "Manage GOST Tunnel" \
        "Dokodemo-Door" "Manage Dokodemo-Door Tunnel" \
        "HA-Proxy" "Manage HA-Proxy Tunnel" \
        "Options" "Additional Configuration Options" \
        "Quit" "Exit From The Script" 3>&1 1>&2 2>&3)

        # Check the return value of the whiptail command
        if [ $? -eq 0 ]; then
            # Check if the user selected a valid option
            case $choice in
                IP-Tables)
                    iptables_menu
                    ;;
                GOST)
                    gost_menu
                    ;;
                Dokodemo-Door)
                    dokodemo_menu
                    ;;
                HA-Proxy)
                    haproxy_menu
                    ;;
                Options)
                    other_options_menu
                    ;;
                Quit)
                    exit 0
                    ;;
                *)
                    whiptail --title "Invalid Option" --msgbox "Please select a valid option." 8 60
                    exit 1
                    ;;
            esac
        else
            exit 1
        fi
    done
}

# Call the menu function
menu
