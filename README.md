# DroneBlocks WiFi Adapter Installation Guide for Go2

This guide explains how to install and configure the BrosTrend AC1L WiFi adapter on your Go2 robot.

## Prerequisites

Before starting either installation method, you'll need:
- Access to your Go2 robot
- An ethernet cable to connect your laptop to the Go2
- The BrosTrend AC1L WiFi adapter

## Initial Connection to Go2

1. Connect ethernet cable between your laptop and the Go2
2. Open a terminal and connect to the Go2:
   ```bash
   ssh unitree@192.168.123.18
   ```
   Password: `123`

## Adapter Installation

### Option A: Offline Installation (Recommended)

This method allows you to install the driver without requiring an internet connection on the Go2.

1. On your laptop with internet access, download and run the offline installer repository:
   ```bash
   git clone git@github.com:DroneBlocks/go2-wifi-adapter.git
   ```

2. Copy the downloaded `ac1l_offline_files` directory to the Go2:
    ```bash
    scp -r go2-wifi-adapter/ac1l_offline_files unitree@192.168.123.18:/home/unitree
    ```

3. ssh into the Go2 and run the offline installer script. The installation may take several minutes to complete:
   ```bash
   ssh unitree@192.168.123.18
   cd /home/unitree/ac1l_offline_files
   sudo ./install-offline.sh
   ```
 
4. Wait until you see "The driver was successfully installed!"

### Option B: Online Installation

This method requires temporarily connecting your Go2 to the internet via USB tethering.

1. Connect your smartphone to the Go2 via USB cable (do not connect the BrosTrend adapter yet)
2. Enable USB tethering on your phone
3. In the Go2's terminal, run:
   ```bash
   sh -c 'wget linux.brostrend.com/install -O /tmp/install && sh /tmp/install'
   ```
4. When prompted, select option `(b)` for the new AC1L model
5. Wait until you see "The driver was successfully installed!" The installation may take several minutes to complete.
6. Disconnect the phone and connect the BrosTrend adapter

## Post-Installation Setup

After completing either installation method:

1. Verify the adapter is recognized:
   ```bash
   iwconfig
   ```
   You should see a `wlan0` device listed

2. Configure NetworkManager to handle the device:
   ```bash
   sudo sed -i 's/managed=false/managed=true/' /etc/NetworkManager/NetworkManager.conf
   sudo systemctl restart NetworkManager
   ```

3. Verify the device is managed:
   ```bash
   nmcli device
   ```

4. Create a WiFi hotspot:
   ```bash
   sudo nmcli connection add type wifi ifname wlan0 con-name Go2-Hotspot autoconnect yes ssid "DroneBlocks-Go2-001" mode ap ipv4.method shared ipv4.addresses "10.42.0.1/24" wifi-sec.key-mgmt wpa-psk wifi-sec.psk "00000000"
   ```

Now, the Go2 should show up as a WiFi network that you can connect to from any device! You can connect using the following credentials:
   - SSID: `DroneBlocks-Go2-001`
   - Password: `00000000`
  
  

## SSH via WiFi

1. Ensure your laptop is connected to the `DroneBlocks-Go2-001` WiFi network.

2. In a new terminal on your laptop, run the ssh command with the Go2's IP address on the WiFi network:
   ```bash
   ssh unitree@10.42.0.1
   ```
   Password: `123`

3. You can now write and run code on the dog without an ethernet cable!


## Running the DroneBlocks Dashboard

If you have installed the DroneBlocks dashboard on your Go2, you can launch it by running this script on your dog:
```bash
python3 dbdash_server.py
```
While connected via WiFi, interacting with the dashboard is the same as when connected via Ethernet, but you should navigate to a different IP address in your browser: `http://10.42.0.1:9000/`
