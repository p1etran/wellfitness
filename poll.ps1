$ErrorActionPreference = 'Stop'
$base = 'https://wellfitness.perfectgym.pl/ClientPortal2'
$hdr  = @{
    'CP-LANG'          = 'pl'
    'CP-MODE'          = 'desktop'
    'X-Requested-With' = 'XMLHttpRequest'
    'Accept'           = 'application/json, text/plain, */*'
}

if ($env:CI) { Start-Sleep -Seconds (Get-Random -Minimum 0 -Maximum 60) }

# --- login ---
$body = @{
    RememberMe = $false
    Login      = $env:GYM_LOGIN
    Password   = $env:GYM_PASS
} | ConvertTo-Json

$login = Invoke-RestMethod -Uri "$base/Auth/Login" -Method Post `
            -ContentType 'application/json;charset=utf-8' `
            -Headers $hdr -Body $body -SessionVariable sess

# token may arrive in the body, or only as a Set-Cookie — cover both
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

# --- append raw ---
@{ ts = (Get-Date).ToUniversalTime().ToString('o'); data = $data } |
    ConvertTo-Json -Compress -Depth 10 |
    Out-File samples.jsonl -Append -Encoding utf8