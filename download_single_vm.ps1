 
param (
    [Parameter(Mandatory=$true)] [string] $g,
    [Parameter(Mandatory=$true)] [string] $u,
    [Parameter(Mandatory=$true)] [string] $n
)

$splitUri=$u.split('/')
$logFileName="c:/temp/"+$splitUri[4]+"_download.log"

remove-item -path $logFileName
echo "DownloadSingleVM called for RG $g, URI $u, path $n" | out-file $logFileName 

$nm="azuresmokestoragesccount"

echo "Importing the context...." | out-file -append $logFileName
Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx' | out-file -append $logFileName

echo "Selecting the Azure subscription..." | out-file -append $logFileName
Select-AzureRmSubscription -SubscriptionId "2cd20493-fe97-42ef-9ace-ab95b63d82c4" | out-file -Append $logFileName
Set-AzureRmCurrentStorageAccount –ResourceGroupName $g –StorageAccountName $nm | out-file -Append $logFileName

echo "Attempting to save the VM..."
Save-AzureRmVhd -Verbose -ResourceGroupName $g -SourceUri $u -LocalFilePath $n -overwrite -NumberOfThreads 10 | out-file -Append $logFileName
echo "Attempt complete..."
       