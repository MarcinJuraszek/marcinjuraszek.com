# Get the new NuGet package version
([string](Get-ChildItem .\nuget\*.sdk.*.nupkg | Select-Object BaseName)) -match 'MyCompany.SDK.([0-9A-Za-z.-]+)' | Out-Null
$packageVersion = $matches[1]

Write-Output "Package version: $packageVersion"

# construct base URLs
$apisUrl = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)/$($env:SYSTEM_TEAMPROJECT)/_apis"
$projectUrl = "$apisUrl/git/repositories/Product"

# create common headers
$headers = @{}
$headers.Add("Authorization", "Bearer $env:SYSTEM_ACCESSTOKEN")

# Get information about master branch in the Product repo
Write-Output "Sending a REST call to get ObjectId of master branch in Product repository"

$masterRefUrl = "$projectUrl/refs?api-version=2.0-preview&filter=heads%2Fmaster"
$masterRefResult = Invoke-RestMethod -Method GET -Headers $headers -Uri $masterRefUrl 
$masterObjectId = $masterRefResult.value[0].objectId

Write-Output "master branch ObjectId: $masterObjectId"

# Fetch packages.config from master branch
$packagesConfigPath = "packages.config"
$itemUrl = "$projectUrl/items?api-version=2.0-preview&versionType=branch&Version=master"
$packagesConfigUrl = "$itemUrl&scopePath=$packagesConfigPath"

Write-Output "Sending a REST call to get latest packages.config content"

$packagesConfig = Invoke-RestMethod -Method GET -Headers $headers -Uri $packagesConfigUrl

# Update the version of MyCompany.SDK package
$packagesConfig = [xml]($packagesConfig.SubString($packagesConfig.IndexOf('<')))
$sdkPackageElement = $packagesConfig.packages.selectSingleNode("package[@id='MyCompany.SDK']")
$sdkPackageElement.setAttribute('version', $packageVersion)

# Create a new branch with the updated packages.config
$headers.Add("Content-Type", "application/json")
$pushUrl = "$projectUrl/pushes?api-version=2.0-preview&versionType=branch&Version=master"
$newBranchRefName = "refs/heads/sdkNugets/$packageVersion"

# Json for creating a new branch
$newBranch = @{
        "refUpdates" = @(@{
            "name" = $newBranchRefName
            "oldObjectId" = $masterObjectId
        })

        "commits" = @(@{
            "comment" = "Updating SDK package version to $packageVersion"
            "changes" = @(@{
                "changeType" = "edit"
                "item" = @{
                    "path" = $packagesConfigPath
                }
                "newContent" = @{
                    "content" = $packagesConfig.OuterXml
                    "contentType" = "rawtext"
                }
            })
        })
    }

$newBranchJson = ($newBranch | ConvertTo-Json -Depth 5)

Write-Output "Sending a REST call to create a new branch 'sdkNugets/$packageVersion' with updated packages.config"

# REST call to create a new branch
$newBranchResponse = Invoke-RestMethod -Method POST -Headers $headers -Body $newBranchJson -Uri $pushUrl

Write-Output "New branch 'sdkNugets/$packageVersion' created."

# Create a Pull Request
$pullRequestUrl = "$projectUrl/pullRequests?api-version=2.0-preview"
$pullRequest = @{
        "sourceRefName" = $newBranchRefName
        "targetRefName" = "refs/heads/master"
        "title" = "Update version of Sdk NuGet package to $packageVersion"
        "description" = "Update versions of MyCompany.SDK NuGet package to $packageVersion"
    }

$pullRequestJson = ($pullRequest | ConvertTo-Json -Depth 5)

Write-Output "Sending a REST call to create a new pull request from sdkNugets/$packageVersion to master"

# REST call to create a Pull Request
$pullRequestResult = Invoke-RestMethod -Method POST -Headers $headers -Body $pullRequestJson -Uri $pullRequestUrl;
$pullRequestId = $pullRequestResult.pullRequestId

Write-Output "Pull request created. Pull Request Id: $pullRequestId"

# Set PR to auto-complete
$setAutoComplete = @{
    "autoCompleteSetBy" = @{
        "id" = $pullRequestResult.createdBy.id
    }
    "completionOptions" = @{
        "mergeCommitMessage" = $pullRequestResult.title
        "deleteSourceBranch" = $True
        "squashMerge" = $True
        "bypassPolicy" = $False
    }
}

$setAutoCompleteJson = ($setAutoComplete | ConvertTo-Json -Depth 5)

Write-Output "Sending a REST call to set auto-complete on the newly created pull request"

# REST call to set auto-complete on Pull Request
$pullRequestUpdateUrl = ($projectUrl + '/pullRequests/' + $pullRequestId + '?api-version=2.0-preview')

$setAutoCompleteResult = Invoke-RestMethod -Method PATCH -Headers $headers -Body $setAutoCompleteJson -Uri $pullRequestUpdateUrl

Write-Output "Pull request set to auto-complete"