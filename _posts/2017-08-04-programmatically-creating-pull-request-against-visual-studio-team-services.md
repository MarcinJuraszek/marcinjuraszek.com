---
layout: post
title: Programmatically creating a Pull Request against Visual Studio Team Services
excerpt_separator: <!--more-->
---

There are certain scenarios, especially when developing software in environment which uses multiple repositories, where certain changes in a single git repository should be followed by another set of changes in another repository or repositories.
Automating these tasks can make Continuous Integration pipeline and entire development system more efficient and let developers focus on writing code instead of manually dealing with multi-repository orchestration.
Let's see how that can be done using custom build scripts in Visual Studio Team Services.

<!--more-->

Consider following setup:
- `mycompany-sdk` - repository with a set of shared tools, libraries, build scripts, etc. 
- `mycompany-productA`, `mycompany-productB`, etc. - repositories with product code - services and applications - built using the sdk

In .NET ecosystem NuGet packages would be used to distribute shared code and tooling from sdk repositories to product repositories.
However, manually keeping the product repositories on the latest version of sdk package might be problematic.
Using version ranges and always picking latest package might work for some people, but it also introduces a new set of problems - without exact version defined in packages.json or .csproj file builds are not repeatable anymore - building the same commit after couple weeks or even hours might pick a new version of dependant package and produce different results.
With exact versioning of dependencies manual update of versions in all product repositories whenever a new version of the package is produced is required.
Using Continues Integration pipeline in VSTS allows that to be automated (either partially of fully, based on your needs).

Visual Studio Team Services exposes a REST API allowing you to perform a lot of the tasks that would usually be performed using the UI.
You can use that API to interact with git repositories: create branches, add commits and create Pull Requests. 

My setup consists of two git repositories in a single VSTS Project:
- `SDK` repository, exporting `MyCompany.SDK` package on every CI build
- `Product` repository which depends on `MyCompany.SDK` package

Both repositories have two build:
- CI build, triggered on merges to master
- Buddy build, triggered on Pull Request by branch policies

Both build definitions have Build and Test steps, but CI build also packages and publishes NuGet package into internal `MyCompanyFeed` feed in VSTS.
`Product` repository uses `nuget restore` command to fetch all the dependent packages before running the build.
The goal is to automatically send a Pull Request to `Product` repository as part of SDK-CI build, with the version of newly published NuGet package.

The flow would be:

1. Get the NuGet package version by parsing .nupkg file name
2. Get ObjectID of master branch in `Product` repository
3. Download top-level `packages.config` file from `Product` repository on that `master` branch
4. Replace version of `MyCompanyFeed` package in `packages.config` file
5. Create a new branch in `Product` repository and push the changes
6. Create a Pull Request, requesting merging newly created branch back to `master`
7. Set the Pull Request to auto-complete, for even less manual intervention

VSTS allows Build definitions to run custom commands, including PowerShell scripts.
That's exactly what we're going to use.
For that let's add `Update-SdkVersionInProductRepository.ps1` script to the repository and `PowerShell` task into SDK-CI build.

![PowerShell task added to SDK-CI build](../../images/vsts-pull-request/powershell-build-task.png)

`Update-SdkVersionInProductRespotiory.ps1` is where the actual logic will be.
First of all, let's get the version of `MyCompany.SDK` from the file name of `nupkg` generated at build.
This step might not be necessary if you're using Build Number as package version.

```powershell
# Get the new NuGet package version
([string](Get-ChildItem .\nuget\*.sdk.*.nupkg | Select-Object BaseName)) -match 'MyCompany.SDK.([0-9A-Za-z.-]+)' | Out-Null
$packageVersion = $matches[1]

Write-Output "Package version: $packageVersion"
```

I'm using *Date and Time*-based versioning, and the script picks the right version:

```
******************************************************************************
Starting: Update Product repository with new SDK version
******************************************************************************
==============================================================================
Task         : PowerShell
Description  : Run a PowerShell script
Version      : 1.2.3
Author       : Microsoft Corporation
Help         : [More Information](https://go.microsoft.com/fwlink/?LinkID=613736)
==============================================================================
. 'd:\a\1\s\scripts\Update-SDKVersionInProductRepository.ps1'
Package version: 1.0.0-CI-20170805-030033
```

Now let's actually interact with VSTS to get `packages.config` from `master` branch of `Product` repository.
The API uses a common base URL for all the methods.
We can use some environment variables set on Build machine to construct that URL.
With the base URL available, constructing all other URLs will be much easier.

```powershell
# construct base URLs
$apisUrl = "$($env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI)/$($env:SYSTEM_TEAMPROJECT)/_apis"
$projectUrl = "$apisUrl/git/repositories/Product"
```

There is also a set of common headers that need to be present on the requests to authenticate them.
Required access token will also be present in environment variables.
Just make sure you enable ***Allow scripts to access OAuth token*** in build options tab.

```powershell
# create common headers
$headers = @{}
$headers.Add("Authorization", "Bearer $env:SYSTEM_ACCESSTOKEN")
```

First of all, we have to get some metadata about `master` branch.

```powershell
# Get information about master branch in the Product repository
Write-Output "Sending a REST call to get ObjectId of master branch in Product repository"

$masterRefUrl = "$projectUrl/refs?api-version=2.0-preview&filter=heads%2Fmaster"
$masterRefResult = Invoke-RestMethod -Method GET -Headers $headers -Uri $masterRefUrl 
$masterObjectId = $masterRefResult.value[0].objectId

Write-Output "master branch ObjectId: $masterObjectId"
```

The ObjectId is a guid-like identifier.
If you run the code above as part of your build you should see something like this in the logs:

```
Sending a REST call to get ObjectId of master branch in Product repository
master branch ObjectId: 99fe4d9bd8acc5c91d92e20e32bcc264642931c3
```

If instead of the ID you see access errors, the build does not have the right permissions.

```
. 'd:\a\1\s\scripts\Update-SDKVersionInProductRepository.ps1'
Package version: 1.0.0-CI-20170805-031931
Sending a REST call to get ObjectId of master branch in Product repository
Invoke-RestMethod : The remote server returned an error: (401) Unauthorized.
master branch ObjectId: 
Process completed with exit code 0 and had 1 error(s) written to the error stream.
```

You have to make sure you enabled ***Allow scripts to access OAuth token*** in build options tab.

![Allow scripts to access oauth token option](../../images/vsts-pull-request/oauth-token.png)

Now that we have the ObjectID we can fetch `packages.config`, modify it and push back to the repository into a new branch.

```powershell
# Fetch packages.config from master branch
$packagesConfigPath = "packages.config"
$itemUrl = "$projectUrl/items?api-version=2.0-preview&versionType=branch&Version=master"
$packagesConfigUrl = "$itemUrl&scopePath=$packagesConfigPath"

Write-Output "Sending a REST call to get latest packages.config content"

$packagesConfig = Invoke-RestMethod -Method GET -Headers $headers -Uri $packagesConfigUrl

$packagesConfig = [xml]($packagesConfig.SubString($packagesConfig.IndexOf('<')))

# Update the version of MyCompany.SDK package
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
```

With that script every build will create a new branch in `Product` repository.
The branch name will contain NuGet package version, which is clearly visible in the log:

```
Sending a REST call to get latest packages.config content
Sending a REST call to create a new branch 'sdkNugets/1.0.0-CI-20170805-041742' with updated packages.config
New branch 'sdkNugets/1.0.0-CI-20170805-041742' created.
```

You can also see that new branch in UI:

![Newly created branch](../../images/vsts-pull-request/branches.png)


As you can see, it's attributes to *Project Collection Build Service ()* account.
You might have to modify that account's permission to make it work. Here's how I set it:

![Build account permissions](../../images/vsts-pull-request/permissions.png)

The two important access controls are **Contribute** and **Create branch**. 

With the branch created, we can update the script to create a Pull Request requesting it to be merged back to master. 

```powershell
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
```

If everything goes right you should see two new lines in the logs:

```
Sending a REST call to create a new pull request from sdkNugets/1.0.0-CI-20170805-043147 to master
Pull request created. Pull Request Id: 1
```

Creating a Pull Request will trigger all the regular validation in `Product` repository - things like build, code review requirements, etc set in Branch Policies for that repository will also be activated.
All that's left is marking the PR as *auto-complete*.

```powershell
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
```

```
******************************************************************************
Starting: Update Product repository with new SDK version
******************************************************************************
==============================================================================
Task         : PowerShell
Description  : Run a PowerShell script
Version      : 1.2.3
Author       : Microsoft Corporation
Help         : [More Information](https://go.microsoft.com/fwlink/?LinkID=613736)
==============================================================================
. 'd:\a\1\s\scripts\Update-SDKVersionInProductRepository.ps1'
Package version: 1.0.0-CI-20170805-044248
Sending a REST call to get ObjectId of master branch in Product repository
master branch ObjectId: d378b91c684074391e340ea3008dbdd2b3bde992
Sending a REST call to get latest packages.config content
Sending a REST call to create a new branch 'sdkNugets/1.0.0-CI-20170805-044248' with updated packages.config
New branch 'sdkNugets/1.0.0-CI-20170805-044248' created.
Sending a REST call to create a new pull request from sdkNugets/1.0.0-CI-20170805-044248 to master
Pull request created. Pull Request Id: 4
Sending a REST call to set auto-complete on the newly created pull request
Pull request set to auto-complete
******************************************************************************
Finishing: Update Product repository with new SDK version
******************************************************************************
```

With all that the pull request will be set to auto-complete, and all that's left is for somebody to approve it!

![Pull Request from Build Agent](../../images/vsts-pull-request/pull-request.png)

Full script is available on GitHub: [https://github.com/MarcinJuraszek/marcinjuraszek.github.io/tree/master/scripts/vsts-pull-request.ps1](https://github.com/MarcinJuraszek/marcinjuraszek.github.io/tree/master/scripts/vsts-pull-request.ps1).