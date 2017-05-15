---
layout: post
title: Solution-wide Rename from Code Fix Provider – Fix async method naming
excerpt_separator: <!--more-->
---

Last time when I posted about [Diagnostic with Code Fix](http://marcinjuraszek.com/2014/04/my-first-diagnostic-with-code-fix-using-roslyn-api.html) using Microsoft .NET Compiler Platform, aka “Roslyn” the fix was completely local. This time, inspired by a [tweet by Luke Sigler](https://twitter.com/Schandlich/status/464474399916040192) ([@Schandlich](https://twitter.com/Schandlich)) I decided to go for solution-wide rename.

<!--more-->

![A Tweet by Luke Sigler](../../images/roslyn-tweet.png)

Idea is very simple: Diagnostic checks every declared method and makes sure, that those marked with async modifier have a name that ends with Async. If not, CodeFix is proposed to fix that issue.

## Diagnostic

Diagnostic part of the problem if extremely simple. The only thing you have to do, is check if method declaration contains `async` modifier, and if its name ends with Async. That’s it:

```
public override void AnalyzeNode(SyntaxNode node, SemanticModel semanticModel, Action<Location, object[]> addDiagnostic, CancellationToken cancellationToken)
{
    var methodDeclaration = node as MethodDeclarationSyntax;
    if (methodDeclaration == null)
        return;

    if (methodDeclaration.Modifiers.Any(SyntaxKind.AsyncKeyword) &&
        !methodDeclaration.Identifier.Text.EndsWith("Async"))
        addDiagnostic(methodDeclaration.Identifier.GetLocation(), new object[] { methodDeclaration.Identifier, methodDeclaration.Identifier.Text + "Async" });
}
```

Method signature differs from the default one you get when implementing `ISyntaxNodeAnalyzer`. That’s because when I started RoslynDiagnostics project, I decided to create abstract class called `SyntaxNodeAnalyzer`, which is a base class for all diagnostics within that project. It just makes some staff easier. You can check how that class looks like on github: [MarcinJuraszek / RoslynDiagnostics / src / RoslynDiagnostics / SyntaxNodeAnalyzer.cs](https://github.com/MarcinJuraszek/RoslynDiagnostics/blob/master/src/RoslynDiagnostics/SyntaxNodeAnalyzer.cs)

## Code Fix

Second part of the store is also not very complicated. The most important peace is the renaming process. Fortunately, Roslyn API provides great solution-wide refactoring experience, which includes *Rename* option. It’s exposed by static class named `Renamer` which can be found in `Microsoft.CodeAnalysis.Rename` namespace. Method we care about is, as you’d probably expect, called `RenameSymbolAsync`:

```
public static async Task<Solution> RenameSymbolAsync(
    Solution solution,
    ISymbol symbol,
    string newName,
    OptionSet optionSet
    CancellationToken cancellationToken = default(CancellationToken))
```

Now, the only thing we have to do is get all necessary data to make `Renamer.RenameSymbolAsync` call. Starting with `ISymbol` symbol:

```
public async override Task<IEnumerable<CodeAction>> GetFixesAsync(Document document, TextSpan span, IEnumerable<Diagnostic> diagnostics, CancellationToken cancellationToken)
{
    var root = await document.GetSyntaxRootAsync(cancellationToken);
    var token = root.FindToken(span.Start);

    var methodDeclaration = token.Parent as MethodDeclarationSyntax;
    if (methodDeclaration == null)
        return null;

    var semanticModel = await document.GetSemanticModelAsync(cancellationToken);
    if (semanticModel == null)
        return null;

    var symbol = semanticModel.GetDeclaredSymbol(methodDeclaration, cancellationToken);
    if (symbol == null)
        return null;
```

All these `null` checks may not be necessary, but just to be safe… Lets move on to `Solution` instance, `OptionsSet` and new method name:

```
    var project = document.Project;
    if (project == null)
        return null;

    var solution = document.Project.Solution;
    if (solution == null)
        return null;

    var options = solution.Workspace.GetOptions();
    var newName = token.Text + "Async";
```

Now, we’re ready to call `Rename` method. But remember – almost entire Roslyn API uses immutable data model, which means instead of modifying instances, you’re getting new ones when content updated. There is no difference here. `Rename` method returns new instance of `Solution` class without modifying the one provided as method parameter:

```
    var newSolution = await Renamer.RenameSymbolAsync(solution, symbol, newName, options);
```

As we’ve now defined how solution should look like after we fix it, we can return `CodeAction` back to IDE:

```
    return new[] { CodeAction.Create("Change method name to '" + newName + "'.", newSolution) };
```

You can find entire class and base CodeFixProvider on github as well.

## Result

Now, we can test our Diagnostic and Code Fix.

Thanks to Roslyn integration within VS, you can see what changes will be made when you use the fix. As you can see, method name rename affects not only method declaration, but also all method calls within entire solution. Also Undo feature plays nice with the fix: hitting *Ctrl+Z* undos rename across entire solution as well.