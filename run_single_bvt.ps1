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
echo "Starting execution of test $testCycle on machine $sourceName" >$transFile 2>&1

Import-AzureRmContext -Path 'C:\Azure\ProfileContext.ctx' >>$transFile 2>&1
Select-AzureRmSubscription -SubscriptionId "$AZURE_SUBSCRIPTION_ID" >>$transFile 2>&1

$tests_failed = $false
.\AzureAutomationManager.ps1 -xmlConfigFile $configFileName -runtests -email –Distro $distro -cycleName $testCycle -UseAzureResourceManager -EconomyMode >>$transFile 2>&1
if ($? -ne $true) {
    $tests_failed = $true
}

if ($tests_failed -eq $true) {
    exit 1
} else {
    exit 0
}