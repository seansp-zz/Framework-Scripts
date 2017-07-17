
$flavor = "CentOS-7.1611"
$flavor = "RHEL72-Smoke-1"

$smokeDelta = "C:\Users\seansp\Desktop\azure_images\original\$flavor-delta.vhd"
$workingFile = "C:\Users\seansp\Desktop\azure_images\$flavor-working.vhd"
Copy-Item -Path $smokeDelta -Destination $workingFile -Force
$vm = New-VM -Name $flavor -VHDPath $workingFile -MemoryStartupBytes 7168mb -Generation 1 -SwitchName "External-WIFI"
start-vm -VM $vm


# copy delta drive to new file.
#new-vm -Name "SBI Smoke 1" -MemoryStartupBytes 7168mb -Generation 1 -SwitchName "External" -VHDPath $originalDrive > $null
