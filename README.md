# WireGuard VPN Deployment in Azure using PowerShell (WIP)

A PowerShell module with commands to create and destroy a VPN using a VM in the Azure cloud as a gateway.

Currently the module can deploy a Debian VM with the necessary network security configuration, public IP address, and SSH access for development.

Two use cases are being pursued. Creating a VPN from the client computer to the cloud gateway. Creating a local VM that routes client traffic through the cloud gateway.

Working on these two configurations has led to learning about Linux network namespaces, iptables, and nftables. It has been insightful, but is not yet successful. Rough notes of previous attempts are kept in the config.md file. Eventually a correct configuration and set of rules will be added to the script.
