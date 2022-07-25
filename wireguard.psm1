param ([Parameter(Mandatory=$true)]
[string]$Location,
[string]$User,
[string]$ResourceGroupName,
[string]$PublicKey)

$ErrorActionPreference = 'Stop'

$AzureProfile = Connect-AzAccount -UseDeviceAuthentication
Write-Output "Using $($AzureProfile.Context.Account.Id)"

$ResourceGroup = Get-AzResourceGroup -ErrorVariable ResourceGroupError -ErrorAction Continue -Location $Location -Name $ResourceGroupName
if ($ResourceGroupError) {
    Write-Output $ResourceGroupError
    Write-Output "Creating missing ResourceGroup"
    $ResourceGroup = New-AzResourceGroup -Location $Location -Name $ResourceGroupName
}
Write-Output "Using ResourceGroup $($ResourceGroup.ResourceGroupName)"

$AvailabilitySet = Get-AzAvailabilitySet -Name "zone0"
if (-not $AvailabilitySet) {
    Write-Output "Creating missing AvailabilitySet"
    $AvailabilitySet = New-AzAvailabilitySet -Location $Location -Name "zone0" -ResourceGroupName $ResourceGroupName -Sku "aligned" -PlatformFaultDomainCount 2
}

# Create a credential with a random password
$PasswordCharacterSet = 'a'..'z' + 'A'..'Z' + '0'..'9'
$Password = ConvertTo-SecureString -AsPlainText ($PasswordCharacterSet | Get-Random -Count 32 | Join-String) -Force
$Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $Password

# Configure networking
Write-Output "Configuring networking"
$NetworkSecurityGroup = Get-AzNetworkSecurityGroup -Name "vpn"
if (-not $NetworkSecurityGroup) {
    $AllowSSHPort = New-AzNetworkSecurityRuleConfig -Name "allow-ssh" -Description "Allow SSH" -Access "allow" -Protocol "Tcp" -Direction "inbound" -Priority 110 -SourceAddressPrefix "Internet" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange 22
    $AllowWireguardPort = New-AzNetworkSecurityRuleConfig -Name "allow-wireguard" -Description "Allow Wireguard" -Access "allow" -Protocol "Udp" -Direction "inbound" -Priority 100 -SourceAddressPrefix "Internet" -SourcePortRange "*" -DestinationAddressPrefix "*" -DestinationPortRange 51820
    $NetworkSecurityGroup = New-AzNetworkSecurityGroup -Location $Location -ResourceGroupName $ResourceGroupName -Name "vpn" -SecurityRules $AllowSSHPort,$AllowWireguardPort
}

$VirtualNetwork = Get-AzVirtualNetwork -Name "vpn-vnet"
if (-not $VirtualNetwork) {
    $SubnetConfig = New-AzVirtualNetworkSubnetConfig -Name "vpn-subnet" -AddressPrefix "10.0.0.0/24"
    $VirtualNetwork = New-AzVirtualNetwork -Name "vpn-vnet" -ResourceGroupName $ResourceGroupName -Location $Location -AddressPrefix "10.0.0.0/16" -Subnet $SubnetConfig
}

$NIC = Get-AzNetworkInterface -Name "wireguard-nic"
if (-not $NIC) {
    $PublicIP = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $Location -Sku "Basic" -Name "wireguard" -AllocationMethod "Dynamic"
    $NIC = New-AzNetworkInterface -Name "wireguard-nic" -ResourceGroupName $ResourceGroupName -Location $Location -SubnetId $VirtualNetwork.Subnets[0].Id -PublicIpAddressId $PublicIP.Id -NetworkSecurityGroupId $NetworkSecurityGroup.Id
}

# Configure the VM
# Choose a debian VM image
# Get-AzVMImagePublisher -Location $Location | Where-Object {$_.PublisherName -eq "Debian"}
# Get-AzVMImageOffer -Location $Location -PublisherName debian
# Get-AzVMImageSku -Location $Location -PublisherName debian -offer debian-11
# Get-AzVMSize -Location $Location | Where-Object {$_.NumberOfCores -le 2} | Where-Object {$_.MemoryInMB -le 1024}
Write-Output "Configuring VM"
$VMConfig = New-AzVMConfig -VMName "wireguard" -VMSize "Standard_B1ls" -AvailabilitySetId $AvailabilitySet.Id
$vm = Set-AzVMSourceImage -VM $VMConfig -PublisherName "Debian" -Offer "debian-11" -Skus "11-gen2" -Version "latest"
$vm = Set-AzVMOperatingSystem -VM $VMConfig -Linux -ComputerName "wireguard" -Credential $Credential
$vm = Add-AzVMNetworkInterface -VM $VMConfig -Id $NIC.Id

# Set authorized SSH public keys
# ED25519 not supported
# https://docs.microsoft.com/en-us/troubleshoot/azure/virtual-machines/ed25519-ssh-keys
Write-Output "Setting SSH key..."
# TODO: Read key from file. Surprisingly finicky...
$vm = Add-AzVMSshPublicKey -VM $VMConfig -KeyData $PublicKey -Path "/home/$User/.ssh/authorized_keys"

# Create the VM
Write-Output "Creating VM..."
$vm = New-AzVM -Location $Location -VM $VMConfig -ResourceGroupName $ResourceGroupName
if ($vm.IsSuccessStatusCode) {
    Write-Output "Successfully created VM"
}
# TODO: Output of New-AzVM is PSAzureOperationResponse instead of PSVirtualMachine in this case
Write-Output "Created VM accessible at $(Get-AzVM -Name wireguard | Get-AzPublicIpAddress | Select-Object -ExpandProperty IpAddress)"
