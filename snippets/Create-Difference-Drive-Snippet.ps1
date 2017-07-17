$parent = "C:\Users\seansp\Desktop\azure_images\original\RHEL72-Smoke-1.vhd"
$delta = "C:\Users\seansp\Desktop\azure_images\original\RHEL72-Smoke-1-delta.vhd"
New-VHD -ParentPath $parent -Path $delta -Differencing

