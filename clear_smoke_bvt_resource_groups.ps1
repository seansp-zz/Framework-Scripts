. C:\Framework-Scripts\common_functions.ps1

login_azure "smoke_source_resource_group" "smokesourcestorageacct"

$names=(Get-AzureRmResourceGroup | Where-Object {$_.ResourceGroupName -like "ICA-RG-BVTDe*"}).ResourceGroupName
get-job | Remove-Job

foreach ($name in $names) {
    $scriptText = " . `"C:\Framework-Scripts\common_functions.ps1`" `
                    login_azure `"smoke_source_resource_group`" `"smokesourcestorageacct`" `
                    Remove-AzureRmResourceGroup -ResourceGroupName $name -force"
    $scriptBlock=[scriptblock]::Create($scriptText)
    start-job -ScriptBlock $scriptBlock
}