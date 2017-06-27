param (
    [Parameter(Mandatory=$true)] [string] $script
)

start-process -FilePath powershell.exe -ArgumentList $script -NoNewWindow