# put in your tenant ID and name suffix of your AVD subscriptions
$tenantId = ""
$avdSubSuffix = ""

function read-avddata {
    [CmdletBinding()]
    param (
        # Defines the source i.e. Cleanup, Redeployment, Patching, ProjectIntake
        [Parameter(Mandatory)]
        [ValidateSet("pools", "sessionhosts")]
        [String]$target
    )

    try {
        # write-log -message "Connect and Fetch all host pools" -path $log
        # Cycle through all subscriptions and collect the host pool information
        $AVDPools = @()
        Get-AzSubscription -TenantId $tenantId | Where-Object { $_.State -eq "Enabled" -and $_.Name -match $avdSubSuffix } | foreach-object {
            # Setting current subscription as context
            set-azcontext -Subscription $_ -Tenant $tenantId | out-null

            # Gathering all AVDPools that are personal and cycle through them
            try {
                $AVDPools += Get-AzWvdHostPool
            }
            catch {
                Write-Error ("Not able to gather host pools:" + $_.Exception.message)
                Exit 1
            }
        }
    }
    catch {
        # write-log -Message "exception $exception has occured gathering host pools" -path $log -Severity Error
        exit
    }

    # Cycling through all hostpools and gather the session host information
    try {
        $AVDs = @()
        # write-log -message "Connect and Fetch all session hosts" -path $log
        $AVDPools | foreach-object {
            # Converting variables for easier read
            $ResourceGroupName = ($_.Id -split "/")[4]
            $SubscriptionID = ($_.Id -split "/")[2]
            $HostPoolName = $_.Name
            # Gathering all AVDPools that are personal and cycle through them
            try {
                $AVDs += Get-AzWvdSessionHost -ResourceGroupName $ResourceGroupName -hostpoolname $HostPoolName -SubscriptionId $SubscriptionID
            }
            catch {
                Write-Error ("Not able to gather session hosts:" + $_.Exception.message) 
                Exit 2
            }
        }
    }
    catch {
        # write-log -Message "exception $exception has occured loading Pools" -path $log -Severity Error
        exit
    }
    return $AVDs
}

function read-azvmdata {
    try {
        # write-log -message "Connect and Fetch all host pools" -path $log
        # Cycle through all subscriptions and collect the host pool information
        $AZVMs = @()
        Get-AzSubscription -TenantId $tenantId | Where-Object { $_.State -eq "Enabled" -and $_.Name -match $avdSubSuffix } | foreach-object {
            # Setting current subscription as context
            set-azcontext -Subscription $_ -Tenant $tenantId | out-null

            # Gathering all AVDPools that are personal and cycle through them
            try {
                $AZVMs += get-azvm -status
            }
            catch {
                Write-Error ("Not able to gather AZVMs:" + $_.Exception.message)
                Exit 1
            }
        }
    }
    catch {
        # write-log -Message "exception $exception has occured gathering host pools" -path $log -Severity Error
        exit
    }
    return $AZVMs
}