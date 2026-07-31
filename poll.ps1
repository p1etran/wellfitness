$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$base = 'https://wellfitness.perfectgym.pl/ClientPortal2'
$csv  = Join-Path $PSScriptRoot 'samples.csv'

# clubs to record — comment out to keep all ~105
$keep = '.'

$hdr = @{
    'CP-LANG'          = 'pl'
    'CP-MODE'          = 'desktop'
    'X-Requested-With' = 'XMLHttpRequest'
    'Accept'           = 'application/json, text/plain, */*'
}

# Small jitter so the poll doesn't hit the portal at the same fixed second
# on every run. Short on purpose — it delays the sample relative to its
# intended slot, and the analysis buckets by hour, so there's nothing to gain
# from a long one.
if ($env:CI) { Start-Sleep -Seconds (Get-Random -Minimum 0 -Maximum 15) }

# --- login ---
if (-not $env:GYM_LOGIN -or -not $env:GYM_PASS) { throw 'GYM_LOGIN / GYM_PASS not set' }

$body = @{
    RememberMe = $false
    Login      = $env:GYM_LOGIN
    Password   = $env:GYM_PASS
} | ConvertTo-Json

$login = Invoke-RestMethod -Uri "$base/Auth/Login" -Method Post `
            -ContentType 'application/json;charset=utf-8' `
            -Headers $hdr -Body $body -SessionVariable sess

$tok = $null
foreach ($f in 'Token','AuthToken','CpAuthToken','access_token') {
    if ($login.PSObject.Properties.Name -contains $f -and $login.$f) { $tok = $login.$f; break }
}
if (-not $tok) {
    $c = $sess.Cookies.GetCookies($base) | Where-Object { $_.Name -eq 'CpAuthToken' }
    if ($c) { $tok = $c.Value }
}
if (-not $tok) { throw 'login succeeded but no token found' }

# --- fetch ---
$get = $hdr.Clone()
$get['Authorization'] = "Bearer $tok"

$data = Invoke-RestMethod -Uri "$base/Clubs/Clubs/GetMembersInClubs" -Method Post `
            -ContentType 'application/json' -Headers $get -WebSession $sess

if (-not $data.UsersInClubList) { throw 'empty UsersInClubList' }

# --- append ---
$ts  = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mmZ')
$enc = New-Object System.Text.UTF8Encoding($false)
$reg = Join-Path $PSScriptRoot 'clubs.csv'
$csv = Join-Path $PSScriptRoot ('samples-{0}.csv' -f (Get-Date).ToUniversalTime().ToString('yyyy-MM'))

# --- club registry, keyed on address ---
$clubs  = [System.Collections.Generic.List[object]]::new()
if (Test-Path $reg) { Import-Csv $reg | ForEach-Object { $clubs.Add($_) } }

$byAddr = @{}
foreach ($c in $clubs) { $byAddr[$c.address] = $c }

$nextId = 1
if ($clubs.Count) {
    $nextId = ($clubs | ForEach-Object { [int]$_.id } | Measure-Object -Max).Maximum + 1
}
$dirty = $false

foreach ($c in $data.UsersInClubList) {
    $addr = $c.ClubAddress.Trim()
    $name = $c.ClubName.Trim()
    if (-not $byAddr.ContainsKey($addr)) {
        $row = [pscustomobject]@{ id = $nextId; name = $name; address = $addr }
        $clubs.Add($row); $byAddr[$addr] = $row; $nextId++; $dirty = $true
        Write-Host "new club: $name"
    } elseif ($byAddr[$addr].name -ne $name) {
        Write-Host "renamed: $($byAddr[$addr].name) -> $name"
        $byAddr[$addr].name = $name; $dirty = $true
    }
}

if ($dirty) {
    $out = @('id,name,address') + ($clubs | ForEach-Object {
        '{0},"{1}","{2}"' -f $_.id, $_.name, $_.address
    })
    [IO.File]::WriteAllLines($reg, [string[]]$out, $enc)
}
# --- samples ---
$lines = $data.UsersInClubList | ForEach-Object {
    '{0},{1},{2}' -f $ts, $byAddr[$_.ClubAddress.Trim()].id, $_.UsersCountCurrentlyInClub
}
if (-not (Test-Path $csv)) { [IO.File]::WriteAllText($csv, "ts,club_id,n`n", $enc) }
[IO.File]::AppendAllLines($csv, [string[]]$lines, $enc)

Write-Host "$ts — $($lines.Count) rows, $($clubs.Count) clubs known"
