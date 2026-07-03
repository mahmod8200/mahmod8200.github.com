# ============================================
# PowerShell HTTP File Server — Dynamic Edition
# Usage: Run as Administrator
# Access: http://YOUR_IP:8080
# ============================================

$basePath = "C:\Users"
$port     = 8080

New-NetFirewallRule -Name "PSFileServer" -DisplayName "PS File Server" `
    -Enabled True -Direction Inbound -Protocol TCP -Action Allow `
    -LocalPort $port -ErrorAction SilentlyContinue | Out-Null

$http = [System.Net.HttpListener]::new()
$http.Prefixes.Add("http://+:$port/")
$http.Start()

$localIP = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.InterfaceAlias -notmatch 'Loopback' } |
    Select-Object -First 1).IPAddress

Write-Host "  Server   : Running" -ForegroundColor Green
Write-Host "  Local    : http://localhost:$port" -ForegroundColor Yellow
Write-Host "  Network  : http://${localIP}:$port" -ForegroundColor Yellow
Write-Host "  Stop     : Ctrl+C" -ForegroundColor Red

function Get-MimeType($ext) {
    switch ($ext.ToLower()) {
        ".html" { "text/html" }          ".htm"  { "text/html" }
        ".css"  { "text/css" }           ".js"   { "application/javascript" }
        ".json" { "application/json" }   ".xml"  { "text/xml" }
        ".txt"  { "text/plain" }         ".log"  { "text/plain" }
        ".ps1"  { "text/plain" }         ".py"   { "text/plain" }
        ".sh"   { "text/plain" }         ".md"   { "text/plain" }
        ".jpg"  { "image/jpeg" }         ".jpeg" { "image/jpeg" }
        ".png"  { "image/png" }          ".gif"  { "image/gif" }
        ".webp" { "image/webp" }         ".svg"  { "image/svg+xml" }
        ".mp4"  { "video/mp4" }          ".webm" { "video/webm" }
        ".mp3"  { "audio/mpeg" }         ".wav"  { "audio/wav" }
        ".pdf"  { "application/pdf" }
        ".zip"  { "application/zip" }    ".rar"  { "application/x-rar-compressed" }
        ".exe"  { "application/octet-stream" }
        default { "application/octet-stream" }
    }
}

function Format-FileSize($bytes) {
    if     ($null -eq $bytes) { "-" }
    elseif ($bytes -ge 1GB)   { "{0:N1} GB" -f ($bytes / 1GB) }
    elseif ($bytes -ge 1MB)   { "{0:N1} MB" -f ($bytes / 1MB) }
    elseif ($bytes -ge 1KB)   { "{0:N1} KB" -f ($bytes / 1KB) }
    else                      { "$bytes B" }
}

function Get-FileIcon($item) {
    if ($item.PSIsContainer) { return "📁" }
    switch ($item.Extension.ToLower()) {
        ".jpg"  { "🖼️" } ".jpeg" { "🖼️" } ".png"  { "🖼️" } ".gif" { "🖼️" }
        ".mp4"  { "🎬" } ".mkv"  { "🎬" } ".avi"  { "🎬" }
        ".mp3"  { "🎵" } ".wav"  { "🎵" } ".flac" { "🎵" }
        ".pdf"  { "📕" }
        ".zip"  { "🗜️" } ".rar"  { "🗜️" } ".7z"   { "🗜️" }
        ".exe"  { "⚙️" } ".dll"  { "⚙️" }
        ".ps1"  { "💻" } ".py"   { "💻" } ".js"   { "💻" }
        ".txt"  { "📝" } ".log"  { "📝" } ".md"   { "📝" }
        ".json" { "📋" } ".xml"  { "📋" } ".csv"  { "📋" }
        default { "📄" }
    }
}

function Test-MobileUA($ua) {
    $ua -match "Mobile|Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini"
}

function Get-Breadcrumb($localPath) {
    $crumbs = "<a href='/'>🏠 Home</a>"
    if ($localPath -ne "/") {
        $parts = $localPath.Trim("/").Split("/")
        $acc   = ""
        foreach ($p in $parts) {
            $acc    += "/$p"
            # FIX #4: HTML-encode breadcrumb segment to prevent XSS
            $safeP   = [System.Net.WebUtility]::HtmlEncode($p)
            $crumbs += " <span>/</span> <a href='$acc'>$safeP</a>"
        }
    }
    return $crumbs
}

function Get-DirectoryHtml($localPath, $fullPath, $isMobile, $search) {
    $allItems = Get-ChildItem $fullPath -ErrorAction SilentlyContinue |
                Sort-Object -Property @{Expression={$_.PSIsContainer}; Descending=$true}, Name

    if ($search) {
        $allItems = $allItems | Where-Object { $_.Name -match [regex]::Escape($search) }
    }

    $rows      = ""
    $itemCount = 0

    if ($localPath -ne "/") {
        $parent = ($localPath -replace "[^/]+/?$", "").TrimEnd("/")
        if (-not $parent) { $parent = "/" }
        if ($isMobile) {
            $rows += "<div class='item folder'><a href='$parent'><span class='ic'>📁</span><span class='info'><span class='nm'>..</span></span></a></div>"
        } else {
            $rows += "<tr class='folder'><td><a href='$parent'><span class='ic'>📁</span> ..</a></td><td>-</td><td>Folder</td><td>-</td></tr>"
        }
    }

    foreach ($item in $allItems) {
        $itemCount++
        $link  = ("$localPath/$($item.Name)").Replace("//", "/")
        $icon  = Get-FileIcon $item
        $size  = if ($item.PSIsContainer) { "-" } else { Format-FileSize $item.Length }
        $date  = $item.LastWriteTime.ToString("dd/MM/yy HH:mm")
        $type  = if ($item.PSIsContainer) { "Folder" } else { $item.Extension.ToUpper().TrimStart(".") }
        $cls   = if ($item.PSIsContainer) { "folder" } else { "file" }
        # FIX #4: HTML-encode file/directory names to prevent XSS
        $safeName = [System.Net.WebUtility]::HtmlEncode($item.Name)

        if ($isMobile) {
            $rows += "<div class='item $cls'><a href='$link'><span class='ic'>$icon</span><span class='info'><span class='nm'>$safeName</span><span class='meta'>$size · $date</span></span></a></div>"
        } else {
            $rows += "<tr class='$cls'><td><a href='$link'><span class='ic'>$icon</span> $safeName</a></td><td>$size</td><td>$type</td><td>$date</td></tr>"
        }
    }

    $breadcrumb = Get-Breadcrumb $localPath
    $searchVal  = if ($search) { [System.Net.WebUtility]::HtmlEncode($search) } else { "" }

    if ($isMobile) {
        return @"
<!DOCTYPE html><html lang='en'><head>
<meta charset='UTF-8'>
<meta name='viewport' content='width=device-width,initial-scale=1,maximum-scale=1'>
<meta name='apple-mobile-web-app-capable' content='yes'>
<title>Files</title>
<style>
*{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#0d1117;color:#c9d1d9;min-height:100vh}
header{background:#161b22;padding:14px 16px;border-bottom:1px solid #30363d;position:sticky;top:0;z-index:10}
.ht{display:flex;align-items:center;margin-bottom:8px}
h1{color:#58a6ff;font-size:1.1em}
.bc{font-size:0.75em;color:#8b949e;white-space:nowrap;overflow-x:auto;margin-bottom:8px}
.bc a{color:#58a6ff;text-decoration:none}
.bc span{color:#30363d;margin:0 3px}
.sf{display:flex;gap:8px}
.sf input{flex:1;background:#21262d;border:1px solid #30363d;border-radius:8px;padding:8px 12px;color:#c9d1d9;font-size:0.9em;outline:none}
.sf button{background:#238636;border:none;border-radius:8px;padding:8px 14px;color:#fff;font-size:0.9em}
.container{padding:12px}
.stats{color:#8b949e;font-size:0.8em;margin-bottom:8px}
.item{background:#161b22;border-radius:10px;margin-bottom:8px;border:1px solid #21262d}
.item:active{background:#1f2937}
.item a{display:flex;align-items:center;gap:12px;padding:14px 16px;text-decoration:none;color:#c9d1d9}
.ic{font-size:1.5em;width:32px;text-align:center;flex-shrink:0}
.info{flex:1;min-width:0}
.nm{display:block;font-size:0.95em;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:#58a6ff}
.meta{display:block;font-size:0.75em;color:#8b949e;margin-top:2px}
.folder .nm{color:#ffa657}
</style></head><body>
<header>
<div class='ht'><h1>📂 File Server</h1></div>
<div class='bc'>$breadcrumb</div>
<form class='sf' method='get'>
<input type='text' name='q' placeholder='Search files...' value='$searchVal'>
<button type='submit'>🔍</button>
</form>
</header>
<div class='container'>
<div class='stats'>$itemCount items</div>
$rows
</div></body></html>
"@
    } else {
        return @"
<!DOCTYPE html><html lang='en'><head>
<meta charset='UTF-8'>
<meta name='viewport' content='width=device-width,initial-scale=1'>
<title>📂 $localPath</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:'Segoe UI',sans-serif;background:#0d1117;color:#c9d1d9;min-height:100vh}
header{background:#161b22;padding:16px 30px;border-bottom:1px solid #30363d;display:flex;align-items:center;gap:16px;flex-wrap:wrap}
h1{color:#58a6ff;font-size:1.2em;white-space:nowrap}
.bc{font-size:0.85em;color:#8b949e;flex:1}
.bc a{color:#58a6ff;text-decoration:none}
.bc a:hover{text-decoration:underline}
.bc span{color:#30363d;margin:0 4px}
.sf{display:flex;gap:8px;margin-left:auto}
.sf input{background:#21262d;border:1px solid #30363d;border-radius:6px;padding:6px 12px;color:#c9d1d9;font-size:0.85em;width:200px;outline:none}
.sf input:focus{border-color:#58a6ff}
.sf button{background:#238636;border:none;border-radius:6px;padding:6px 12px;color:#fff;cursor:pointer;font-size:0.85em}
.container{padding:20px 30px}
.stats{color:#8b949e;font-size:0.82em;margin-bottom:12px}
table{width:100%;border-collapse:collapse;background:#161b22;border-radius:10px;overflow:hidden;border:1px solid #30363d}
th{background:#21262d;padding:11px 16px;text-align:left;color:#8b949e;font-size:0.82em;font-weight:600;border-bottom:1px solid #30363d}
td{padding:10px 16px;border-bottom:1px solid #1a1f27;font-size:0.88em}
tr:last-child td{border-bottom:none}
tr:hover td{background:#1a2030}
a{color:#58a6ff;text-decoration:none}
a:hover{text-decoration:underline}
.ic{margin-right:6px}
td:nth-child(2),td:nth-child(3),td:nth-child(4){color:#8b949e}
.folder a{color:#ffa657}
</style></head><body>
<header>
<h1>📂 File Server</h1>
<div class='bc'>$breadcrumb</div>
<form class='sf' method='get'>
<input type='text' name='q' placeholder='Search...' value='$searchVal'>
<button type='submit'>Search</button>
</form>
</header>
<div class='container'>
<div class='stats'>$itemCount items</div>
<table>
<thead><tr><th>Name</th><th>Size</th><th>Type</th><th>Modified</th></tr></thead>
<tbody>$rows</tbody>
</table>
</div></body></html>
"@
    }
}

function Get-404Html($path) {
    $safePath = [System.Net.WebUtility]::HtmlEncode($path)
    return "<!DOCTYPE html><html><head><meta charset='UTF-8'><meta name='viewport' content='width=device-width,initial-scale=1'><style>body{background:#0d1117;color:#c9d1d9;font-family:sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;text-align:center}h1{color:#f85149;font-size:3em}p{color:#8b949e;margin-top:10px}a{color:#58a6ff}</style></head><body><div><h1>404</h1><p>$safePath not found</p><p><a href='/'>Back to home</a></p></div></body></html>"
}

# FIX #5: Graceful shutdown via try/finally
try {
    while ($http.IsListening) {
        try {
            $ctx       = $http.GetContext()
            $req       = $ctx.Request
            $res       = $ctx.Response
            $localPath = [System.Uri]::UnescapeDataString($req.Url.LocalPath)
            $query     = $req.QueryString["q"]
            $isMobile  = Test-MobileUA $req.UserAgent

            # FIX #1 + #2: Normalize path to prevent traversal via '..' and prefix collision
            $joined   = Join-Path $basePath $localPath.TrimStart('/')
            $fullPath = [System.IO.Path]::GetFullPath($joined)
            $baseNorm = $basePath.TrimEnd('\')

            if (-not ($fullPath -eq $baseNorm -or $fullPath.StartsWith($baseNorm + '\'))) {
                $res.StatusCode = 403
                $buf = [System.Text.Encoding]::UTF8.GetBytes("<h1>403 Forbidden</h1>")
                $res.ContentType = "text/html"
                $res.OutputStream.Write($buf, 0, $buf.Length)
                $res.Close(); continue
            }

            $device = if ($isMobile) { "📱" } else { "🖥️" }
            Write-Host "$(Get-Date -Format 'HH:mm:ss') $device $localPath" -ForegroundColor DarkGray

            if (-not (Test-Path $fullPath)) {
                $res.StatusCode = 404
                $buf = [System.Text.Encoding]::UTF8.GetBytes((Get-404Html $localPath))
                $res.ContentType = "text/html; charset=utf-8"
                $res.OutputStream.Write($buf, 0, $buf.Length)
            }
            elseif (Test-Path $fullPath -PathType Container) {
                $html = Get-DirectoryHtml $localPath $fullPath $isMobile $query
                $buf  = [System.Text.Encoding]::UTF8.GetBytes($html)
                $res.ContentType = "text/html; charset=utf-8"
                $res.OutputStream.Write($buf, 0, $buf.Length)
            }
            else {
                # FIX #3: Stream large files instead of loading into RAM
                $ext        = [System.IO.Path]::GetExtension($fullPath)
                $fname      = [System.IO.Path]::GetFileName($fullPath)
                $fileStream = [System.IO.File]::OpenRead($fullPath)
                $res.ContentType     = Get-MimeType $ext
                $res.ContentLength64 = $fileStream.Length
                $res.Headers.Add("Content-Disposition", "inline; filename=`"$fname`"")
                $fileStream.CopyTo($res.OutputStream)
                $fileStream.Close()
            }

            $res.Close()
        }
        catch {
            Write-Host "Error: $_" -ForegroundColor Red
            try { $ctx.Response.Close() } catch {}
        }
    }
}
finally {
    $http.Stop()
    $http.Close()
    Write-Host "Server stopped." -ForegroundColor Red
}
