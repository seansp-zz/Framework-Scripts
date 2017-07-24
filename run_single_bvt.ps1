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
echo "Starting execution of test $testCycle on machine $sourceName" 2>&1 | out-file $transFile -Force

Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx' 2>&1 | out-file $transFile -Append
Select-AzureRmSubscription -SubscriptionId "$AZURE_SUBSCRIPTION_ID" 2>&1 | out-file $transFile -Append

$tests_failed = $false
cd C:\azure-linux-automation
git pull 2>&1 | out-file $transFile -Append
.\AzureAutomationManager.ps1 -xmlConfigFile $configFileName -runtests -email –Distro $distro -cycleName $testCycle -UseAzureResourceManager -EconomyMode 2>&1 | out-file $transFile -Append
if ($? -ne $true) {
    $tests_failed = $true
}

if ($tests_failed -eq $true) {
    exit 1
} else {
    exit 0
}