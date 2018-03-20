---
layout: post
title: Compile TypeScript in ASP.NET 5 application using grunt-typescript
excerpt_separator: <!--more-->
---

Today was a big day for entire .NET Framework community. **So much amazing stuff announced on VisualStudio Connect(); event in NY**: [open sourcing Core .NET Framework code](http://bit.ly/1zNzeOG) (including CLR, JIT, FC, BLC and more), [Visual Studio 2015 Preview](http://blogs.msdn.com/b/visualstudioalm/archive/2014/11/12/announcing-visual-studio-2015-preview-availability.aspx) with free and extensible Visual Studio Community Edition, [new Visual Studio Online features](http://blogs.msdn.com/b/bharry/archive/2014/11/12/news-from-connect.aspx) and more. Also quite a few [announcements connected to ASP.NET 5](http://blogs.msdn.com/b/webdev/archive/2014/11/12/announcing-asp-net-features-in-visual-studio-2015-preview-and-vs2013-update-4.aspx). The new version of ASP.NET, known before as ASP.NET vNext, that will **revolutionize the way people create Web Applications using .NET Framework stack**. Particular feature I’d like to focus on today is great integration with Grunt – JavaScript task runner that can be used to automate routine development tasks, e.g. compiling LESS/SASS files to CSS, CoffeeScript/TypeScript to JavaScript and more.

<!--more-->

Official ASP.NET 5 documentation contains a tutorial how to [use Grunt to compile LESS files to CSS style sheets on the fly](http://www.asp.net/vnext/overview/aspnet-vnext/grunt-and-bower-in-visual-studio-2015) every time you build your app. **I’ll should you how to use the same task runner to compile TypeScript code to JavaScript as part of your app build process.**

Let’s start with new ASP.NET 5 project created in Visual Studio 2015 Preview using *File > New Project > Visual C# > Web > ASP.NET Web Application* and selecting **“ASP.NET 5.0 Starter Web”** from the list of available Web projects.
 
![New project](../../images/typescript-pipeline/NewProject.png)

![New ASP.NET Project](../../images/typescript-pipeline/AspProjectType.png)

As you will probably notice when solution is created folder structure is quite different than what you should know from previous ASP.NET projects. However, I will not focus on describing what’s the role of particular folders and files. You should know that **there are two files important for Grunt: gruntfile.js and package.js**.

![Solution Structure](../../images/typescript-pipeline/SolutionStructure.png)

But we’ll get to them later. Let’s create TypeScript file we’d like to compile. I’m going to create new directory in the solution called Scripts. **It will be place for all TypeScript files in my application.** To keep things simple I will create just one file: myApp.ts which will have a simple TypeScript function. Unfortunately TypeScript is not available within *New Item* dialog. You have to pick different one (e.g. Text File) and manually change file extension to *.ts*.

![Add New Item](../../images/typescript-pipeline/AddTypeScriptFile.png)

After doing so you could see new file in solution explorer

![myAppFile](../../images/typescript-pipeline/myAppFile.png)

Function I’d like to compile to JavaScript is really simple

```typescript
function longerThan10(value: string): boolean {
    return value.length > 10;
}
```

OK, back to *package.json* and *gruntfile.js*. We’re going to use *package.json* to import grunt packages that will perform TypeScript compilation. **Packages we need are grunt-typescript and typescript and we can add them by modifying *package.json* file.** Visual Studio editor will help you with nice intellisence suggesting correct package name and latest available versions.

![Package.json](../../images/typescript-pipeline/PackageJson.png)

Now we have to download the packages using context menu invoked when right clicked on NPM in Solution Explorer and selecting *Restore Packages*.

![Restore packages](../../images/typescript-pipeline/RestorePackages.png)

As you’ll notice both packages added to package.json will show up on the list as *(not installed)*. **That comment should go away when you restore the packages.**

So we have the packages declared and they are successfully added into the solution and restored. Now we have to **declare the task that will actually perform necessary compilation**. To do that we have to modify *gruntfile.js* content. There are two thing that needs to be added:

– Package instalation code, at the end of the file
– Package task definition within grunt.initConfig

Final *gruntfile.js* content should be as follows:

```javascript
// This file in the main entry point for defining grunt tasks and using grunt plugins.
// Click here to learn more. http://go.microsoft.com/fwlink/?LinkID=513275&clcid=0x409

module.exports = function (grunt) {
    grunt.initConfig({
        bower: {
            install: {
                options: {
                    targetDir: "wwwroot/lib",
                    layout: "byComponent",
                    cleanTargetDir: false
                }
            }
        },
        typescript: {
            base: {
                src: ['Scripts/**/*.ts'],
                dest: 'wwwroot/app.js',
                options: {
                    module: 'amd',
                    target: 'es5'
                }
            }
        },
    });

    // This command registers the default task which will install bower packages into wwwroot/lib
    grunt.registerTask("default", ["bower:install"]);

    // The following line loads the grunt plugins.
    // This line needs to be at the end of this this file.
    grunt.loadNpmTasks("grunt-bower-task");
    grunt.loadNpmTasks("grunt-typescript");
};
```

Now we can run the task to make sure it does what we want it to do. There is a new window added to Visual Studio called **Task Runner Explorer**. You can invoke if from *View > Other Windows > Task Runner Explorer*. It’s show you all tasks defined in your solution, let you ran them and set bindings to run tasks automatically pre or after build. Right click on typescript and select Run to run the task and compile your TypeScript code to JavaScript.

![Task Runner Explorer](../../images/typescript-pipeline/TaskRunnerExplorer.png)

If you did everything right you should see run results saying  that *wwwroot\app.js* file was created

![Run results](../../images/typescript-pipeline/RunResults.png)

and new file should show up in Solution Explorer

![myAppJs](../../images/typescript-pipeline/myAppJs.png)

It will contain our TypeScript function compiled to JavaScript:

```javascript
function longerThan10(value) {
    return value.length > 10;
}
```

To make it more natural you can set the task to run every time Build is performed Using** Bindings > After Build** option.

![Post Build Binding](../../images/typescript-pipeline/PostBuildBinding.png)

To confirm that it works you can either change source in myApp.ts and rebuild – *app.js* content should change as well. You can also remove app.js. Performing a build should make it appear again.