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

if ($env:CI) { Start-Sleep -Seconds (Get-Random -Minimum 0 -Maximum 60) }

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
$ts = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mmZ')

$lines = $data.UsersInClubList |
    Where-Object { $_.ClubName -match $keep } |
    ForEach-Object { '{0},"{1}",{2}' -f $ts, $_.ClubName, $_.UsersCountCurrentlyInClub }

if (-not $lines) { throw 'filter matched no clubs — check $keep' }

$enc = New-Object System.Text.UTF8Encoding($false)
if (-not (Test-Path $csv)) {
    [IO.File]::WriteAllText($csv, "ts,club,n`n", $enc)
}
[IO.File]::AppendAllLines($csv, [string[]]$lines, $enc)

Write-Host "$ts — wrote $($lines.Count) rows"
