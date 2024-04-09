$ErrorActionPreference = "Stop"

$update_machine = Get-VM -Name "Update Machine"

# Get update machine information
$update_disk = $update_machine | Get-VMHardDiskDrive

$update_disk_info = $update_disk | Select-Object Path | Get-VHD | Where-Object {$_.VhdType -eq "Differencing"}

$root_disk = Get-VHD -Path $update_disk_info.ParentPath


# Get info on depending machines
$vms = Get-VM | Where-Object {$_.Name -ne $update_machine.Name}

$disks = $vms | Get-VMHardDiskDrive

$disks_info = $disks | Select-Object Path | Get-VHD -ErrorAction 'silentlycontinue' | Where-Object {$_.ParentPath -eq $root_disk.Path}

$disks = $disks | Where-Object {$_.Path -in $disks_info.Path}

$target_vms = $vms | Where-Object {$_.Name -in $disks.VMName}

$all_vms = $target_vms + $update_machine

# Start working

Write-Output "Shutting down VMs"
$running_vms = $all_vms | Where-Object {$_.State -ne "Off"}
$running_vms | Stop-VM -AsJob | Receive-Job -Wait -AutoRemoveJob

try {
    Write-Output "Removing old differencing disks"
    $disks | Remove-Item
    
    Write-Output "Merging update disk"
    Merge-VHD -Path $update_disk_info.Path -Destination $root_disk.Path
    
    $root_disk | Optimize-VHD -Confirm -Mode Prezeroed
} finally {
    $all_child_disks = $disks + $update_disk
    
    Write-Output "Replacing differencing disks"
    $all_child_disks | New-VHD -ParentPath $root_disk.Path -Differencing
}

Write-Output "Starting stopped VMs"
$running_vms | Where-Object {$_.Name -ne $update_machine.Name}| Start-VM -AsJob | Receive-Job -Wait -AutoRemoveJob
