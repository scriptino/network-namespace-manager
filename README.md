# 🛠️ Network Namespace Manager Script  

## 📌 Overview  
This Bash script allows you to manage **network namespaces** on a Linux system, providing full network isolation by assigning interfaces to separate namespaces.  
It features a **menu-driven** interface to simplify the creation, management, and deletion of namespaces, as well as running programs within them. The script can be safely executed. It does not modify any system files. The only files that the script creates and deletes are 'logs' and 'configuration' files (located in the `/tmp` directory). The temporary file for Conky is created in `/home/user_name/.config/conky/myns/`. Upon the creation of each namespace, a `resolv.conf` file for the nameserver (DNS) is also created in `/etc/netns/namespace_name/resolv.conf`. Note: the global `/etc/resolv.conf` file is not touched.  All changes made with the 'ip' commands are completely reversible and temporary; in the worst-case scenario, everything can be restored by rebooting the operating system, although it should never be necessary. 

**⚠️ Note on Wi-Fi Interfaces**  
Wi-Fi interfaces **cannot be moved** into a network namespace due to the way the Linux **mac80211** stack handles wireless connections globally. If you need to use a Wi-Fi connection inside a namespace, consider creating a **virtual Ethernet pair (veth)** or using **a bridge** with NAT (Network Address Translation) to forward traffic.

## 🚀 Features  
- **📡 View namespaces and interfaces** → Lists existing namespaces, network interfaces, and their respective **IP addresses** and **gateways**.  
- **🔧 Create a network namespace** →  
  1. Select a network interface.  
  2. Assign a name to the namespace.  
  3. The script creates the namespace, moves the interface into it, and launches a minimal **Conky** instance for network monitoring.  
- **🖥️ Run programs inside a namespace** →  
  - Choose a namespace and execute a program in isolation.  
  - Execution options:  
    - **Interactive** (the terminal remains attached to the program output).  
    - **Background** (the program runs in the background, keeping the terminal free).  
- **🗑️ Delete namespaces** →  
  - Stops the Conky instance.  
  - Moves the interfaces back to the root namespace.  
  - Deletes the namespace.  
- **🧹 Clear terminal** → Clears the terminal screen.  
- **❌ Exit** → Exits the script.  

## 📦 Prerequisites  
- **iproute2** → Required to create and manage network namespaces
- **Bash** → The script is written in Bash and must be executed in a Bash shell.  
- **sudo** → Superuser privileges are required for network operations.  
- **Conky** (optional) → For network monitoring inside namespaces. 

## ⚙️ Installation  
Download the script and make it executable:  
```bash
chmod +x network_namespace_manager.sh
```

## ▶️ Usage  

Run the script with superuser privileges:  
```bash
sudo ./network_namespace_manager.sh
```

### 📜 Main Menu:  

When executed, the script displays the following menu:  

```plaintext
Network Namespace Manager
1) Show available namespaces  
2) Create a network namespace  
3) Run programs inside a namespace  
4) Delete namespaces  
5) Clear console  
6) Exit  
```

## 🔍 Examples  

### 📡 Isolating a Network Interface  

```bash
sudo ./network_namespace_manager.sh
# Select option 2
# Select the network interface
# Assign a name to the namespace
```  

🔹 The interface will be **isolated** from the main system network!  

### 🌐 Running a Web Browser in Isolation  

```bash
sudo ./network_namespace_manager.sh
# Select option 3
# Choose the namespace
# Run a browser like w3m or firefox/chromium
```  

🔹 The browser's network activity will be **fully isolated** from the system.  

### 🗑️ Deleting a Namespace  

```bash
sudo ./network_namespace_manager.sh
# Select option 4
# Choose the namespace to delete
```  

🔹 The interface will be moved back to the root namespace.  

## 📜 Logging  

All actions are logged in a file for debugging and auditing purposes:  
📍 **Log file location**: `/tmp/namespace_manager.log`  
🔹 Includes **INFO** and **ERROR** messages for troubleshooting.  

## 🤝 Contributing  

Want to improve the script? Feel free to contribute:  

1. Fork the repository on **GitHub**.  
2. Modify the code or improve the documentation.  
3. Submit a **pull request** with your changes.  

### 🤖 Credits

This script was made possible thanks to the vast knowledge of **ChatGPT** and **DeepSeek**. 🚀

## 📜 License  

This script is released under the **MIT License**. You are free to use, modify, and distribute it.  

---  

📌 The script is now ready to use. Follow the instructions above to get started.  
