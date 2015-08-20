param(
[string]$K2Server = "localhost", 
[int]$K2Port = "5555",
[string]$adFilterQuery = "(sAMAccountName=Bulk*)",
[string]$ldapPath = "LDAP://DC=DENALLIX,DC=COM",
[string]$netbiosName = "DENALLIX"
)



Add-Type -AssemblyName ("SourceCode.Security.UserRoleManager.Management, Version=4.0.0.0, Culture=neutral, PublicKeyToken=16a2c5aaaa1b130d")
Add-Type -AssemblyName ("SourceCode.HostClientAPI, Version=4.0.0.0, Culture=neutral, PublicKeyToken=16a2c5aaaa1b130d")

Function GetK2ConnectionString{
	Param([string]$k2hostname, [int] $K2port = 5555)

	$constr = New-Object -TypeName SourceCode.Hosting.Client.BaseAPI.SCConnectionStringBuilder
	$constr.IsPrimaryLogin = $true
	$constr.Authenticate = $true
	$constr.Integrated = $true
	$constr.Host = $K2hostname
	$constr.Port = $K2port
	return $constr.ConnectionString
}


Function ResolveUser{
	Param($urm, $user)
	
	$swResolve = [Diagnostics.Stopwatch]::StartNew()
	Write-Debug "Resolving user $user"
	
	$fqn = New-Object -TypeName SourceCode.Hosting.Server.Interfaces.FQName -ArgumentList $user
	$urm.ResolveIdentity($fqn, [SourceCode.Hosting.Server.Interfaces.IdentityType]::User, [SourceCode.Hosting.Server.Interfaces.IdentitySection]::Identity)
	Write-Debug "Resolved $user Identity in $($swResolve.ElapsedMilliseconds)ms."
	$urm.ResolveIdentity($fqn, [SourceCode.Hosting.Server.Interfaces.IdentityType]::User, [SourceCode.Hosting.Server.Interfaces.IdentitySection]::Members)
	Write-Debug "Resolved $user Members in $($swResolve.ElapsedMilliseconds)ms."
	$urm.ResolveIdentity($fqn, [SourceCode.Hosting.Server.Interfaces.IdentityType]::User, [SourceCode.Hosting.Server.Interfaces.IdentitySection]::Containers)
	Write-Debug "Resolved $user Containers in $($swResolve.ElapsedMilliseconds)ms."
	Write-Host "Resolved user $user in $($swResolve.ElapsedMilliseconds)ms."
}


Function ResolveGroup{
	Param($urm, $group)
	
	$swResolve = [Diagnostics.Stopwatch]::StartNew()
	Write-Debug "Resolving group $group"
	
	$fqn = New-Object -TypeName SourceCode.Hosting.Server.Interfaces.FQName -ArgumentList $group
	$urm.ResolveIdentity($fqn, [SourceCode.Hosting.Server.Interfaces.IdentityType]::Group, [SourceCode.Hosting.Server.Interfaces.IdentitySection]::Identity)
	Write-Debug "Resolved group $fqn Identity in $($swResolve.ElapsedMilliseconds)ms."
	$urm.ResolveIdentity($fqn, [SourceCode.Hosting.Server.Interfaces.IdentityType]::Group, [SourceCode.Hosting.Server.Interfaces.IdentitySection]::Members)
	Write-Debug "Resolved group $fqn Members in $($swResolve.ElapsedMilliseconds)ms."
	$urm.ResolveIdentity($fqn, [SourceCode.Hosting.Server.Interfaces.IdentityType]::Group, [SourceCode.Hosting.Server.Interfaces.IdentitySection]::Containers)
	Write-Debug "Resolved group $fqn Containers in $($swResolve.ElapsedMilliseconds)ms."
	Write-Host "Resolved group $group in $($swResolve.ElapsedMilliseconds)ms."
}

$sw = [Diagnostics.Stopwatch]::StartNew()

Write-Host "Starting K2 ResolveUser script."
Write-Debug "$($sw.ElapsedMilliseconds)ms: Connecting to AD. Ldap: $ldap - Filter: $adFilterQuery"

$dirEntry = New-Object System.DirectoryServices.DirectoryEntry($ldap)
$searcher = New-Object System.DirectoryServices.DirectorySearcher($dirEntry)
	
$searcher.Filter = $adFilterQuery
$searcher.PageSize = 1000;
$searcher.SearchScope = "Subtree"
$searcher.PropertiesToLoad.Add("sAMAccountName") | Out-Null
$searcher.PropertiesToLoad.Add("objectClass") | Out-Null
$searcher.PropertiesToLoad.Add("whenChanged") | Out-Null

Write-Debug "$($sw.ElapsedMilliseconds)ms: Starting FindAll()"
$searchResult = $searcher.FindAll()
Write-Debug "$($sw.ElapsedMilliseconds)ms: Completed FindAll."

$usersToResolve = @()
$groupsToResolve = @()

Write-Host "Searching AD using filter: $adFilterQuery"
foreach ($result in $searchResult) {
	$props = $result.Properties
    $fqn = [string]::Concat("K2:", $netbiosName, "\", $props.samaccountname)
	if ($props.objectclass.Contains("user") -eq $true) {
        $usersToResolve += $fqn
        Write-Debug "$($sw.ElapsedMilliseconds)ms: Adding $fqn to list of users to resolve."
    } elseif($props.objectclass.Contains("group") -eq $true) {
        $groupsToResolve += $fqn
        Write-Debug "$($sw.ElapsedMilliseconds)ms: Adding $fqn to list of groups to resolve."
    } else {
        Write-Debug "$($sw.ElapsedMilliseconds)ms: Skipping $($objResult.Path) - Not a User/Group ObjectClass"
    }
}
Write-Host "Found $($usersToResolve.Count) users to resolve. Found $($groupsToResolve.Count) groups to resolve. Time used until now: $($sw.ElapsedMilliseconds)ms."
Write-Debug "$($sw.ElapsedMilliseconds)ms: Cleaning up AD resources..."
$searchResult.Dispose()
$searcher.Dispose()
$dirEntry.Dispose()


Write-Host "Starting user resolution loop. Time used until now: $($sw.ElapsedMilliseconds)ms."
$constr = GetK2ConnectionString -K2Hostname $K2Server -K2Port $K2Port
Write-Debug "$($sw.ElapsedMilliseconds)ms: Using K2 connection string: $constr"

$urm = New-Object SourceCode.Security.UserRoleManager.Management.UserRoleManager
$urm.CreateConnection() | Out-Null
$urm.Connection.Open($constr) | Out-Null
Write-Host "Connected to K2 server: $K2Server"

if ($usersToResolve.Count -gt 0) {
    Write-Host "Starting user resolution for $($usersToResolve.Count) users"
    foreach ($user in $usersToResolve) {
        ResolveUser -urm $urm -user $user
    }
} else {
    Write-Host "No users to resolve."
}

if ($groupsToResolve.Count -gt 0) {
    Write-Host "Starting group resolution for $($groupsToResolve.Count) groups"
    foreach ($group in $groupsToResolve) {
        ResolveGroup -urm $urm -group $group
    }
} else {
    Write-Host "No groups to resolve."
}

$urm.Connection.Close();

Write-Host "K2 ResolveUser script completed in $($sw.ElapsedMilliseconds)ms."

