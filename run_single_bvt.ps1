param (
    [Parameter(Mandatory=$true)] [string] $sourceName="Unknown",
    [Parameter(Mandatory=$true)] [string] $configFileName="Unknown",
    [Parameter(Mandatory=$true)] [string] $distro="Smoke-BVT",
    [Parameter(Mandatory=$true)] [string] $testCycle="BVT"
)

. "C:\Framework-Scripts\secrets.ps1"

#
#  Launch the automation
$transFile="c:\temp\transcripts\" + $sourceName + "_transcript.log"
Start-Transcript -Path c:\temp\bvt_transcripts\$transFile

Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx'
Select-AzureRmSubscription -SubscriptionId "$AZURE_SUBSCRIPTION_ID"

$tests_failed = $false
cd C:\azure-linux-automation
.\AzureAutomationManager.ps1 -xmlConfigFile $configFileName -runtests -email –Distro $distro -cycleName $testCycle -UseAzureResourceManager -EconomyMode
if ($? -ne $true) {
    $tests_failed = $true
}

if ($tests_failed -eq $true) {
    Write-Host "BVTs for $sourceName have failed.  Transcript can be found in $transFile" -ForegroundColor Red
} else { 
    Write-Host "BVTs for $sourceName have passed.  Transcript can be found in $transFile" -ForegroundColor Green
}

Stop-Transcript
if ($tests_failed -eq $true) {
    exit 1
} else {
    exit 0
}