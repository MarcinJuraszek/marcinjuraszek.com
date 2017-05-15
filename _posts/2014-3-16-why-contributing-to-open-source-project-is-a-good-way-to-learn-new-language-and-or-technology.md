---
layout: post
title: Introducing CloneExtensions .NET cloning library
excerpt_separator: <!--more-->
---

I’ve been trying to learn F# for quite a long time now, but there was never a good way to do it. First of all, I need some way to evaluate my work. It’s really easy to learn new language, but **you never know if you’re using it right**. That’s even more likely to happen when not only language is new but also general idea behind that language is much different. That’s the case with my F# learning. Almost every programming language I’ve used so far can be classified as object-oriented-first language. F# is different. It’s functional-first language and because of that it’s more about learning how functional programming looks like, not how F# syntax looks like. But I think I found a way to learn F# right. And the answer is: Open Source.

<!--more-->

There’s probably another question on your mind now: **Why is Open Source a good way to learn F# (or new language in general)?** I can think about couple reasons why it’s true, but two of them are in my opinion the most important:

#### 1. You get real-person mentoring and code review for free as part of Fork & Pull model

That’s really, really important. Every time you submit a pull request there is another person who will most likely go through your code and check if it’s good enough. Of course, **how good the feedback is depends on particular project you decide to contribute to**. For some projects you can just be ignored, but if you choose wisely and you’re lucky, it will be really valuable opinion.

#### 2. You can work on real-life cases, not on tutorials and Hello World! samples

Most of the time, when you’re trying to learn a new language you start with Hello World! And most of the time it looks really easy. Then you try to search for some courses or tutorials to check more complicated cases. But even then you sometimes realize that’s not really it. **Being able to write Hello World! in 100 languages doesn’t mean you know 100 languages.** That’s why you need real-life scenarios. You want to know how to use that particular language to solve real-life problems. And again, Open Source is a good way to get that knowledge. **There are probably hundreds and thousands of projects you can dig into and learn how other people solves these problems.** And when you feel comfortable enough, you can contribute and train that knowledge in practice.

###Does it really work?

I may not be the best proof of that concept, because I’ve started going that way just couple days ago, but I already see many benefits. But words may not be good enough, so it’s time for real time example.

Because I’m trying to learn F# I decided to contribute to [Visual F# Power Tools](https://github.com/fsprojects/VisualFSharpPowerTools):

> Visual F# Power Tools is a community effort to bring useful F# VS extensions into a single home (…)

First of all, I went through [Contributing Guidelines](https://github.com/fsprojects/VisualFSharpPowerTools/blob/master/CONTRIBUTING.md) and existing codebase to see, how the project is maintained. Then, I chose an issue I decided to work on: [Add support for folder organization](https://github.com/fsprojects/VisualFSharpPowerTools/issues/116). **Why this particular Issue?** Mostly because it doesn’t look that complicated, and because, if done wrong, won’t mess existing functionality. Of course, that was my decision. You can make different one, and e.g. start with some bug-fixes, to force yourself deeper into existing codebase.

But anyway, I worked on that folder organization support item for two days, to come up with working code! You can see my first commit to forked codebase here: [Folder organization support](https://github.com/MarcinJuraszek/VisualFSharpPowerTools/commit/88123b37328e47c2f6bd757f693f5518efd6faaf). As you can see, **there is a lot of comments from other contributions**, even before a pull request was made! And most important, they are all really valuable. My first attempt contained following peace of code:

```
let isCommandEnabled action = 
    let items = getSelectedItems()
    let projects = getSelectedProjects()
    match items.Length, projects.Length with
    | 1, 0 -> 
        let item = items.[0]
        SolutionExplorerHelper.isFSharpProject item.ContainingProject.Kind 
        && (SolutionExplorerHelper.isPhysicalFolder item.Kind || action = Action.NewAbove || action = Action.NewBelow)
    | 0, 1 -> SolutionExplorerHelper.isFSharpProject projects.[0].Kind && action = Action.New
    | _, _ -> false
```

If you’re at least a little bit familiar with F# you may think: **Why is he doing it that crazy way?!** Well, I’m asking myself exact same question now :) But thanks to [Vasily Kirichenko](https://github.com/vasily-kirichenko) now I know it should be done this way:

```
let isCommandEnabled action = 
    let items = getSelectedItems()
    let projects = getSelectedProjects()
    match items, projects with
    | [item], [] -> 
        SolutionExplorerHelper.isFSharpProject item.ContainingProject.Kind 
        && (SolutionExplorerHelper.isPhysicalFolder item.Kind || action = Action.NewAbove || action = Action.NewBelow)
    | [], [project] -> SolutionExplorerHelper.isFSharpProject project.Kind && action = Action.New
    | _, _ -> false
```

Another example is all about knowing language features and standard libraries which comes with language itself. That’s probably the most problematic part of switching to/learning new language. You may quickly catch up with new syntax, but unless you know most popular and useful libraries used with that language, you’re not as productive as you could be in well-known environment **You write code which works, but is much more complicated than it’s necessary.** I got a really good example of that.

```
let private getSelected<'T> (dte:DTE2) =
    let items = dte.ToolWindows.SolutionExplorer.SelectedItems :?> UIHierarchyItem[]
    items
    |> Seq.map (fun i -> i.Object)
    |> Seq.map (fun o -> match o with | :? 'T as p -> Some(p) | _ -> None)
    |> Seq.filter (fun o -> match o with | Some _ -> true | None -> false)
    |> Seq.map (fun o -> o.Value)
```

Looks fine, works fine, but it does not mean it is fine. That’s because F# has another method in `Seq` module to perform exactly that kind of selection. It’s called `Seq.choose`:

```
let private getSelected<'T> (dte:DTE2) =
    let items = dte.ToolWindows.SolutionExplorer.SelectedItems :?> UIHierarchyItem[]
    items
    |> Seq.choose (fun x -> 
            match x.Object with
            | :? 'T as p -> Some p
            | _ -> None)
```

It does look cleaner, doesn’t it?

These are just two examples of really good and valuable feedback I already got about my F# code. Finally, after another hour of refactoring, I was confident enough to submit a [Pull Request with my new feature](https://github.com/fsprojects/VisualFSharpPowerTools/pull/188). I don’t know if that request will be accepted, but even if it’s not, I still feel that **I learned a lot of new stuff while working on it**. And I’m pretty confident that I’m learning functional programming programming and F# the right way. I can also feel, that it’s something much closer to solving real programming problems, not just writing *Hello World!* for N-th time. **So it’s already a win.**