---
layout: post
title: Folders in F# projects. How to do it? What to avoid?
excerpt_separator: <!--more-->
---

I’ve been working on a new feature for [Visual F# Power Tools](https://github.com/fsprojects/VisualFSharpPowerTools) extension, which would creating and maintaining folder structure within F# projects. I have to admit, **it was not a pleasure to dig into VS SDK and try to get it working**. The most annoying part: part of SDK related to Solution Explorer still uses COM interfaces… Second most annoying part: Solution Explorer complaining about completely correct project structure…

<!--more-->

But anyway. The more I dig into it, the more weird behaviors I experienced. And because **I don’t think I’m the only one struggling with folders in F# projects** – there are couple questions on StackOverflow about this (like [here](http://stackoverflow.com/q/5918534/1163867) and [here](http://stackoverflow.com/q/5396465/1163867)) – and because there is also a known workaround how to force VS to show folders in your project – just manually edit `.fsproj` file – I decided to write about couple of problems you may run into trying to force F# project to contain folders.

## How to do it?

As mentioned before, you can already **add a folder to F# project manually modifying project file**. Let’s start with an empty *F# Library* project structure:

![Empty F# Library](../../images/folders-solution-explorer.png)

If you look into project file itself, either using different editor or using *Unload Project -> Edit ***.fsproj* you’ll see that it’s just an XML file with different kind of information about your project. A part which is important in our case it this one:

```xml
    <ItemGroup>
        <Compile Include="Library1.fs" />
        <None Include="Script.fsx" />
    </ItemGroup>
```

It contains list of files project is build from, in exact **same order they appear in Solution Explorer** window. The only thing you have to do to add a folder it change that part of XML file. Let’s say I’d like to have folder called Utile as the first item in the project. It will be a place to store all utility and helper modules for my library. To start slowly, just two files to begin with: `Math.fs` and `Reflection.fs`:

```xml
    <ItemGroup>
        <Compile Include="Utils\\Reflection.fs" />
        <Compile Include="Utils\\Math.fs" />
        <Compile Include="Library1.fs" />
        <None Include="Script.fsx" />
    </ItemGroup>
```

Saving the file will cause Visual Studio to show a dialog saying, that project file had changed from outside the environment and it has to be reloaded. Reloading shows your new project structure:

![New project structure](../../images/folder-WithUtils.png)

Looks cool. Problem is, **there is no a single file or folder created on your disc!** If you try to build the project, you’ll see following errors:

```
Source file '(...)\FoldersTutorialLibrary\FoldersTutorialLibrary\Utils\Math.fs' could not be found
Source file '(...)\FoldersTutorialLibrary\FoldersTutorialLibrary\Utils\Reflection.fs' could not be found
You have to create a folder and files manually. After doing so, you’ll be able to successfully build a project. All standard project rules still apply. It means that files are still compiled top-down, according to order they appear within fsproj file. You can see it looking at Output window:
C:\Program Files (x86)\Microsoft SDKs\F#\3.1\Framework\v4.0\fsc.exe -o:obj\Debug\FoldersTutorialLibrary.dll -g –debug:full –noframework –define:DEBUG –define:TRACE –doc:bin\Debug\FoldersTutorialLibrary.XML –optimize- –tailcalls- -r:”C:\Program Files (x86)\Reference Assemblies\Microsoft\FSharp\.NETFramework\v4.0\4.3.1.0\FSharp.Core.dll” -r:”C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.5\mscorlib.dll” -r:”C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.5\System.Core.dll” -r:”C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.5\System.dll” -r:”C:\Program Files (x86)\Reference Assemblies\Microsoft\Framework\.NETFramework\v4.5\System.Numerics.dll” –target:library –warn:3 –warnaserror:76 –vserrors –validate-type-providers –LCID:1033 –utf8output –fullpaths –flaterrors –subsystemversion:6.00 –highentropyva+ –sqmsessionguid:5baf4dbf-ff26-48a6-98fb-bb698d0582a2 “C:\Users\marcin\AppData\Local\Temp\.NETFramework,Version=v4.5.AssemblyAttributes.fs” Utils\Reflection.fs Utils\Math.fs Library1.fs
```

To change that order, you have to modify project file again, and move some files around. But, you have to keep files from the same directory together. That’s why in out sample, you can’t make `Library1.fs` compile before `Reflection.fs` but after `Math.fs`:

```xml
    <ItemGroup>
        <Compile Include="Utils\\Math.fs" />
        <Compile Include="Library1.fs" />
        <Compile Include="Utils\\Reflection.fs" />
        <None Include="Script.fsx" />
    </ItemGroup>
```

That kind of structure will give you an error when you try loading it in Visual Studio:

![Incorrect configuration](../../images/folders-Incorrect.png)

Getting back to correct structure. When you already have a folder, you can add new files to it using *Right click -> Add -> New Item*. **Most of the time it will be added correctly**. What might be surprising, you can also easily add subfolder to already existing one using Visual Studio UI! Standard *Right click -> Add -> New Folder* works just fine.

![New folder](../../images/folders-NewFolder.png)

But, to make that folder appear after reloading your project, it has to contain at least one file when you close your solution.

OK, so now you know how to add folders to F# project let’s talk about the other part of the story.

## What to avoid?

###Don’t add folder with the same name twice. No matter where within project it is!

That’s probably the most crazy behavior I’ve run into. **Folder names must be unique within the entire project!** Yes, you read it correctly, unique within the entire project. It means considering following folder structure:

```xml
    <ItemGroup>
        <Compile Include="Utils\Helpers\ReflectionHelper.fs" />
        <Compile Include="Utils\Reflection.fs" />
        <Compile Include="Utils\Math.fs" />
        <Compile Include="Helpers\Helper.fs" />
        <Compile Include="Library1.fs" />
        <None Include="Script.fsx" />
    </ItemGroup>
```

You’ll get exact same error saying, that *opening a project would cause a folder to appear twice within Solution Explorer*. Why? I have no idea…

### Don’t use Add Above / Add Below.

Another interesting issue I found is connected to *Add Above* and *Add Below* commands. Trying to add new item above `Utils\\Reflection.fs` makes the project structure look like that:

![Add Above/Below](../../images/folders-AddAbove.png)

Not even close to what you’d expect, is it?


## Should I do it?

I’m pretty sure that list of issues is not closed. I’ve personally run into couple more issue, which couldn’t be reproduced later when I tried to do so! And because of that **I would not advice you to introduce complicated folder structure into your F# projects**. But, even with these issues, knowledge how to add a folder when you really need it, e.g. within huge project may make your F# project much easier to navigate and organize. I would though stay on one-level structure. Adding nested folders seems to increase chance of facing issues in future.