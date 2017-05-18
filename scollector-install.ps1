$uri = 'https://github.com/bosun-monitor/bosun/releases/download/0.5.0/scollector-windows-amd64.exe'
$install_dir = "${env:ProgramFiles}/scollector"
if ([IntPtr]::Size -eq 4) {
    $uri = 'https://github.com/bosun-monitor/bosun/releases/download/0.5.0/scollector-windows-386.exe'
}
$regex_version = '((\d+\.)?(\d+\.)?(\*|\d+))'
$new_version = [regex]::match($uri, ".*/($regex_version)/").Groups[1].Value
$need_install = $true

if (!(Get-Command nssm)) {
    Write-Error "I can't find nssm, quitting"
    Exit 1
}

function put_config_in_dir {
    param([string]$tomldir)

    $conf = 
    @"
Host = "docker.streambox.com:8070"

[[Process]]
Name = "^LogonUI$"
[[Process]]
Name = "pmapper" # Streambox activation server relies on port mapping
[[Process]]
Name = "ACTSvc" # Streambox activation server
[[Process]]
Name = "^EncoderFD1.*"
[[Process]]
Name = "^transport[HS]D.*"
[[Process]]
Name = "^httpd$"
[[Process]]
Name = "^rotatelogs$"
[[Process]]
Name = "^ApacheMonitor$"
[[Process]]
Name = "^php$"
[[Process]]
Name = "^sfr$"
[[Process]]
Name = "^(chrome|firefox|iexplore|opera)$"
[[Process]]
Name = "^(MSSQLSERVER|SQLSERVERAGENT)$"
[[Process]]
Name = "^scollector"
[[Process]]
Name = "^mysqld"
[[Process]]
Name = "^mysql$"
[[Process]]
Name = "^node$"
[[Process]]
Name = "^SLS$"
[[Process]]
Name = "^service$"
[[Process]]
Name = "^Bandwidth$"
[[Process]]
Name = "^ifbserver$"
[[Process]]
Name = "^bash$"
[[Process]]
Name = "^sh$"
[[Process]]
Name = "^tmux$"
[[Process]]
Name = "^mintty$"
[[Process]]
Name = "^(emacs-nox|emacsclient)$"
[[Process]]
Name = "^vim$"
[[Process]]
Name = "^sshd$"
[[Process]]
Name = "^ssh$"
[[Process]]
Name = "^ssh-agent$"
[[Process]]
Name = "^putty$"
[[Process]]
Name = "^cmd$"
[[Process]]
Name = "^powershell$"
[[Process]]
Name = "^SearchIndexer$"
[[Process]]
# Driver for Presonus for IFBServer
Name = "^AudioBox$"
[[Process]]
Name = "^nssm$"
[[Process]]
Name = "^(transcoder|Transcoder)$"
[[Process]]
Name = "^mplayer$"
[[Process]]
Name = "^mencoder$"
[[Process]]
Name = "^SearchIndexer$"
"@

    # make sure scollector.toml and scollector-windows-386.exe are siblings
    # scollector-windows-386.exe looks for filename scollector.toml specifically
    New-Item -Type Directory -Force $tomldir >$null
    Set-Content -Encoding ascii "$tomldir/scollector.toml" -value $conf
}


$glob = "${env:SYSTEMDRIVE}/Program*/scollector/scollector*.exe"
$binpath = Get-ChildItem $glob -ea 0 | Select-Object -Last 1 | Select-Object -exp fullname
if ($binpath -ne $null) {
    $out = & $binpath --version
    $version = [regex]::match($out, ".*version ($regex_version)").Groups[1].Value
    if ([Version]$new_version -le [Version]$version) {
        $need_install = $false
    }
}

put_config_in_dir $install_dir

$is_service_installed = $false
if (Get-WmiObject win32_service | 
        Where-Object { $_.Name -like '*scollector*' -and $_.StartMode -eq 'Auto' }) {
    $is_service_installed = $true
}

Function Get-SCP { Get-Process | Where-Object { $_.Name -like '*scollector*' } }
do { Get-SCP | Stop-Process -force; Sleep -s 0.25; }while ($(Get-SCP))

if ($need_install) {

    mkdir -force $install_dir >$null
    $scbin = Split-Path ([System.Uri]$uri).AbsolutePath -leaf
    if ([Version]$PSVersionTable.PSVersion -ge [Version]"3.0") {
        Invoke-WebRequest -Uri $uri -OutFile "$install_dir/$scbin"
    }
    else {
        (new-object System.Net.WebClient).DownloadFile($uri, "$install_dir/$scbin")
    }
}

$glob = "${env:SYSTEMDRIVE}/Program*/scollector"
$install_dir = Get-ChildItem $glob -ea 0 | Select-Object -Last 1 | Select-Object -exp fullname
$glob = "${env:SYSTEMDRIVE}/Program*/scollector/scollector*.exe"
$binpath = Get-ChildItem $glob -ea 0 | Select-Object -Last 1 | Select-Object -exp fullname

nssm stop scollector confirm
nssm remove scollector confirm
nssm install scollector $binpath
nssm set scollector Start SERVICE_AUTO_START
# nssm set scollector AppParameters "-conf $install_dir\scollector.toml"
nssm set scollector DisplayName scollector
nssm set scollector Description "Collect machine statistics to send to bosun"
nssm set scollector AppDirectory $install_dir
nssm set scollector AppStderr "$install_dir\scollector.err"
nssm start scollector
