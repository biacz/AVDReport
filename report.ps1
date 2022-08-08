# put in your tenant ID and name suffix of your AVD subscriptions
$tenantId = ""
$avdSubSuffix = ""
$Site = ""
$List = ""

import-module Az
import-module pnp.powershell

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

try {
    try {
        # Reading AVD data
        Write-Verbose -Verbose -Message "# Reading AVD data"
        $AVDs = read-avddata -target sessionhosts
    }
    catch {
        Write-Error ($_.Exception.message)
        #Exit 2
    }
  
    try {
        # Creating base_report powershell object from data
        Write-Verbose -Verbose -Message "# Creating base_report powershell object from data"
        $base_report = $AVDs | select-object @{n = "VMName"; e = { $($_.ResourceId -split "/")[-1] } }, 
        @{n = "HostPool"; e = { $($_.Name -split "/")[0] } }, 
        @{n = "Subscription"; e = { $($_.ResourceId -split "/")[2] } },
        @{n = "ResourceGroupName"; e = { $($_.ResourceId -split "/")[4] } }, 
        @{n = "SessionHostName"; e = { $($_.Name -split "/")[1] } },
        AssignedUser, AllowNewSession, OSVersion, AgentVersion, ResourceId
    }
    catch {
        Write-Error ($_.Exception.message)
        #Exit 3
    }
 
    # Connecting to Sharepoint List  
    write-verbose -Verbose -Message "# Connecting to Sharepoint List"
    Connect-PnPOnline $Site -credentials $pnpCreds
    write-verbose -message "Connecting to PNP $Site - List $List" -verbose
    $List = Get-PnpList $List
  
    # Querying list items
    write-verbose -Verbose -Message "# Querying list items"
    $items = Get-PnPListItem -List $List
  
    #Create a New Batch 
    $pnpBatch = New-PnPBatch
    $counter = 0
  
    # Looping through items for orphaned objects
    write-verbose -verbose -message 'Looping through items for orphaned objects'
    $items | foreach-object {
        if ($_.FieldValues.Title -notin $base_report.ResourceId) {
            Remove-PnPListItem -Identity $($_.id | Select-Object -first 1) -List $List -Batch $pnpBatch
            write-output "Delete entry for: $($_.FieldValues.Title)"
        }
    }
  
    # Looping through base_report to update existing items and add new
    write-verbose -verbose -message 'Looping through base_report to update existing items and add new'
    $base_report | foreach-object {
        $baseItem = $_
        $params = @{
            "Title"             = [string]$baseItem.ResourceId
            "Subscription"      = [string]$baseItem.Subscription
            "ResourceGroupName" = [string]$baseItem.ResourceGroupName
            "VMName"            = [string]$baseItem.VMName
            "SessionHostName"   = [string]$baseItem.SessionHostName
            "AssignedUser"      = [string]$baseItem.AssignedUser
            "HostPool"          = [string]$baseItem.HostPool
            "AllowNewSession"   = [string]$baseItem.AllowNewSession
            "OSVersion"         = [string]$baseItem.OSVersion
            "AgentVersion"      = [string]$baseItem.AgentVersion
        }
      
        $hit = $items | where-object { $_.FieldValues.Title -eq $baseItem.ResourceId }
        if ($hit) {
            try {
                set-pnplistitem -List $List -Identity $($hit.Id | Select-Object -first 1) -Values $params -batch $pnpBatch 
            }
            catch {
                write-verbose -message ($_.Exception.message) -verbose
                #Exit 10
            }
        }
        if ($baseItem.ResourceId -notin $items.FieldValues.Title) {
            Add-PnPListItem -List $List -Values $params -batch $pnpBatch
        }
        $counter++
        if ($counter -ge 500) {
            # Send pnp batch to SPO
            write-verbose -verbose -message 'Send pnp batch to SPO'
            Invoke-PnPBatch -Batch $pnpBatch
            $counter = 0
        }
    }
    Invoke-PnPBatch -Batch $pnpBatch
}
catch {
    Write-Error ($_.Exception.message)
    #Exit 4
}