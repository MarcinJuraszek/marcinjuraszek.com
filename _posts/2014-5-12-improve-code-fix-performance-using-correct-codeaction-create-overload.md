---
layout: post
title: Improve Code Fix performance using correct CodeAction.Create overload
excerpt_separator: <!--more-->
---

In my previous post I wrote about [solution-wide Rename Code Fix using Roslyn](http://marcinjuraszek.com/2014/05/solution-wide-rename-from-code-fix-provider-fix-async-method-naming.html), which is supposed to **analyze method declarations and suggest a fix** when method marked with  async    modifier does not have a name that ends with Async. The code I suggested works just fine, however there were some comments about **improvements that can be made to make it work better**. In this post I’m trying to address one of the suggestions, what results in seconds version of `AsyncMethodNameAnalyzer` and `AsyncMethodNameFix`.

<!--more-->

## CodeAction.Create overloads

When implementing `ICodeFixProvider.GetFixesAsync` method, which returns `Task<IEnumerable<CodeAction>>` you have couple possible ways to return `CodeAction` class instance. That’s because `CodeAction.Create` factory method has couple overloads you can choose from:

```csharp
public static CodeAction Create(string description, Document changedDocument)
public static CodeAction Create(string description, Solution changedSolution)
public static CodeAction Create(string description, IEnumerable<CodeActionOperation> operations)
public static CodeAction Create(string description, Func<CancellationToken, Task<Document>> createChangedDocument)
public static CodeAction Create(string description, Func<CancellationToken, Task<Solution>> createChangedSolution);
public static CodeAction Create(string description, Func<CancellationToken, Task<IEnumerable<CodeActionOperation>>> createOperations)
```

As you can see, there is pair of methods with **one taking object** (modified solution, document or set of operations to perform) and **another one taking delegate which returns a task typed to return the same object**. You may expect, that under the hoods, they should both be somehow modified to follow the same path during further execution. And you are correct. Look at `Solution` and `Func<CancellationToken, Task<Solution>>` pair implementation:

```csharp
public static CodeAction Create(string description, Func<CancellationToken, Task<Solution>> createChangedSolution)
{
    if (description == null)
    {
        throw new ArgumentNullException("description");
    }

    if (createChangedSolution == null)
    {
        throw new ArgumentNullException("createChangedSolution");
    }

    return new SolutionChangeAction(description, createChangedSolution);
}
```

```csharp
public static CodeAction Create(string description, Solution changedSolution)
{
    if (description == null)
    {
        throw new ArgumentNullException("description");
    }

    if (changedSolution == null)
    {
        throw new ArgumentNullException("changedSolution");
    }

    return new SolutionChangeAction(description, (ct) => Task.FromResult(changedSolution));
}
```

As you can see, version which does not use Task is modified to used it, using `Task.FromResult`. **Which one should I use then?** To answer that question we should answer another one: **why does it actually matters?**

## When is Code Fix code executed by Visual Studio?

Quick debugging session gives us answer to that question: **`ICodeFixProvider.GetFixesAsync` is invoked every time user puts an IP on a token/node diagnostic was added at.** That’s the token/node where you see a green wave-like underline within editor. On the other hand, **delegate you pass to `CodeAction.Create` method is invoked when use clicks on that little floating thing with a light bulb**.

It means, that by passing a delegate instead of modified document/solution directly when using `CodeAction.Create` you can **delay heavy computation execution until it’s really necessary** – when user is trying to invoke your Code Fix. Calculating how document/solution should look like in `ICodeFixProvider.GetFixesAsync` directly, makes it run even if user just wants to see what fixes are available, and then decides not to use any of suggested.

## Does it really matter?

It depends. In cases when your Code Fix is really simple, e.g. you’re just moving around couple nodes within syntax tree, it probably won’t make any difference. However, when your fix is more complicated, requires changes in entire solution (like rename does), it really makes a difference, and you should use a delegate when creating CodeAction instance. I would advice you to **use an overload which takes a delegate by default**, and switch to the other one only when there is really a good reason to do so.

## Fixed Rename refactoring, v2

Because of all the reasons above, I modified `AsyncMethodNameFix` to use proper `CodeAction.Create` overload. Final code is:

```csharp
return new[] {  CodeAction.Create("Change method name to '" + newName + "'.",  (ct) => Renamer.RenameSymbolAsync(solution, symbol, newName, options, ct))};
```

You have to admit, change is really small. But it makes a difference, gives users better experience and calculates solution-wide rename only when user really wants to use it. That’s definitely way to go.