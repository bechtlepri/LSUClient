﻿function Save-LSUpdate {
    <#
        .SYNOPSIS
        Downloads a Lenovo update package to disk

        .PARAMETER Package
        The Lenovo package or packages to download

        .PARAMETER Proxy
        Specifies a proxy server for the connection to Lenovo. Enter the URI of a network proxy server.

        .PARAMETER ProxyCredential
        Specifies a user account that has permission to use the proxy server that is specified by the -Proxy
        parameter.

        .PARAMETER ProxyUseDefaultCredentials
        Indicates that the cmdlet uses the credentials of the current user to access the proxy server that is
        specified by the -Proxy parameter.

        .PARAMETER ShowProgress
        Shows a progress animation during the downloading process, recommended for interactive use
        as downloads can be quite large and without any progress output the script may appear stuck

        .PARAMETER Force
        Redownload and overwrite packages even if they have already been downloaded previously

        .PARAMETER Path
        The target directory to which to download the packages to. In this directory,
        a subfolder will be created for each downloaded package.
    #>

	[CmdletBinding()]
    Param (
        [Parameter( Position = 0, ValueFromPipeline = $true, Mandatory = $true )]
        [pscustomobject]$Package,
        [Uri]$Proxy,
        [pscredential]$ProxyCredential,
        [switch]$ProxyUseDefaultCredentials,
        [switch]$ShowProgress,
        [switch]$Force,
        [System.IO.DirectoryInfo]$Path = "$env:TEMP\LSUPackages"
    )
    
    begin {
        $transfers = [System.Collections.Generic.List[System.Threading.Tasks.Task]]::new()
    }
    
    process {
        foreach ($PackageToGet in $Package) {
            $DownloadDirectory = Join-Path -Path $Path -ChildPath $PackageToGet.id

            if (-not (Test-Path -Path $DownloadDirectory -PathType Container)) {
                Write-Verbose "Destination directory did not exist, created it: '$DownloadDirectory'`r`n"
                $null = New-Item -Path $DownloadDirectory -Force -ItemType Directory
            }

            $PackageDownload = $PackageToGet.URL -replace "[^/]*$"
            $PackageDownload = [String]::Concat($PackageDownload, $PackageToGet.Extracter.FileName)
            $DownloadPath    = Join-Path -Path $DownloadDirectory -ChildPath $PackageToGet.Extracter.FileName

            if ($Force -or -not (Test-Path -Path $DownloadPath -PathType Leaf) -or (
               (Get-FileHash -Path $DownloadPath -Algorithm SHA256).Hash -ne $PackageToGet.Extracter.FileSHA)) {
                # Checking if this package was already downloaded, if yes skipping redownload
                $webClient = New-WebClient -Proxy $Proxy -ProxyCredential $ProxyCredential -ProxyUseDefaultCredentials $ProxyUseDefaultCredentials
                $transfers.Add( $webClient.DownloadFileTaskAsync($PackageDownload, $DownloadPath) )
            }
        }
    }
    
    end {
        if ($ShowProgress -and $transfers) {
            Show-DownloadProgress -Transfers $transfers
        } else {
            while ($transfers.IsCompleted -contains $false) {
                Start-Sleep -Milliseconds 500
            }
        }

        if ($transfers.Status -contains "Faulted" -or $transfers.Status -contains "Canceled") {
            $errorString = "Not all packages could be downloaded, the following errors were encountered:"
            foreach ($transfer in $transfers.Where{ $_.Status -in "Faulted", "Canceled"}) {
                $errorString += "`r`n$($transfer.AsyncState.AbsoluteUri) : $($transfer.Exception.InnerExceptions.Message)"
            }
            Write-Error $errorString
        }
        
        foreach ($webClient in $transfers) {
            $webClient.Dispose()
        }
    }
}