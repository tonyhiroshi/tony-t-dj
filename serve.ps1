# tony-t-dj local dev server
# Usage:  pwsh ./serve.ps1   ->  http://localhost:8145/
# ASCII-only on purpose so it parses under both Windows PowerShell 5.1 and pwsh 7.
$port = 8145
$root = $PSScriptRoot

$mime = @{
  ".html" = "text/html; charset=utf-8"; ".js" = "text/javascript; charset=utf-8";
  ".json" = "application/json; charset=utf-8"; ".svg" = "image/svg+xml";
  ".css" = "text/css; charset=utf-8"; ".png" = "image/png";
  ".jpg" = "image/jpeg"; ".jpeg" = "image/jpeg"; ".gif" = "image/gif"; ".webp" = "image/webp";
  ".mp3" = "audio/mpeg"; ".wav" = "audio/wav"; ".txt" = "text/plain; charset=utf-8";
  ".ico" = "image/x-icon"; ".webmanifest" = "application/manifest+json";
}

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://localhost:$port/")
try {
  $listener.Start()
} catch {
  Write-Host ("Failed to start: " + $_.Exception.Message) -ForegroundColor Red
  Write-Host "Port $port may already be in use." -ForegroundColor Yellow
  exit 1
}

Write-Host ""
Write-Host "  tony-t-dj -> http://localhost:$port/" -ForegroundColor Cyan
Write-Host "  Stop: Ctrl+C" -ForegroundColor DarkGray
Write-Host ""

try {
  while ($listener.IsListening) {
    $ctx = $null
    try {
      $ctx = $listener.GetContext()
      $path = [System.Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath.TrimStart("/"))
      if ([string]::IsNullOrEmpty($path)) { $path = "index.html" }
      $file = Join-Path $root $path

      # no-cache: always serve the file fresh from disk during development
      $ctx.Response.Headers.Add("Cache-Control", "no-store, no-cache, must-revalidate")

      if ((Test-Path $file -PathType Leaf) -and ($file.StartsWith($root))) {
        $ext = [System.IO.Path]::GetExtension($file).ToLower()
        $ctx.Response.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { "application/octet-stream" }
        # Range support (HTTP 206) so audio seeking works like on GitHub Pages
        $fs = [System.IO.File]::OpenRead($file)
        try {
          $len = $fs.Length
          $start = 0; $end = $len - 1
          $ctx.Response.Headers.Add("Accept-Ranges", "bytes")
          $range = $ctx.Request.Headers["Range"]
          if ($range -and $range -match '^bytes=(\d*)-(\d*)$') {
            if ($Matches[1] -ne '') { $start = [int64]$Matches[1]; if ($Matches[2] -ne '') { $end = [Math]::Min([int64]$Matches[2], $len - 1) } }
            elseif ($Matches[2] -ne '') { $start = [Math]::Max(0, $len - [int64]$Matches[2]) }
            $ctx.Response.StatusCode = 206
            $ctx.Response.Headers.Add("Content-Range", "bytes $start-$end/$len")
          }
          $count = $end - $start + 1
          $ctx.Response.ContentLength64 = $count
          $fs.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null
          $buf = New-Object byte[] 65536
          while ($count -gt 0) {
            $n = $fs.Read($buf, 0, [int][Math]::Min($buf.Length, $count))
            if ($n -le 0) { break }
            $ctx.Response.OutputStream.Write($buf, 0, $n)
            $count -= $n
          }
        } finally { $fs.Dispose() }
      } else {
        $ctx.Response.StatusCode = 404
        $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: " + $path)
        $ctx.Response.OutputStream.Write($msg, 0, $msg.Length)
      }
    } catch {
      # one bad request must not kill the server
      Write-Host ("Request error: " + $_.Exception.Message) -ForegroundColor DarkYellow
    } finally {
      if ($ctx) { try { $ctx.Response.Close() } catch {} }
    }
  }
} finally {
  $listener.Stop()
}
