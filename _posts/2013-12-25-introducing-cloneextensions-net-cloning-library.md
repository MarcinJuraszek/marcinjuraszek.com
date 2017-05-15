---
layout: post
title: Introducing CloneExtensions .NET cloning library
excerpt_separator: <!--more-->
---

I’ve spent last two days working on my first open source .NET library named [CloneExtensions](https://cloneextensions.codeplex.com/). It gives you a smart way to clone your object instances without implementing any interface writing any additional `Clone` method at all. It uses Expression Tree to compile that `Clone` method for you right before you’re trying to use `GetClone` for given type `T` for the first time.

Project is in early phase but even now you can use it to clone plenty of different types:

- Primitive (`int`, `uint`, `byte`, `double`, `char`, etc.), known immutable types (`DateTime`, `TimeSpan`, `String`) and delegates (including `Action`, `Func<T1, TResult>`, etc)
- Nullable
- `T[]` arrays
- Custom classes and structs, including generic classes and structs.

Following class/struct members are cloned internally:

- Values of public, not readonly fields
- Values of public properties with both get and set accessors
- Collection items for types implementing `ICollection`

If you’re interested in how it works internally look at [documentation](https://cloneextensions.codeplex.com/documentation), where Expression Tree creation logic is described with additional samples.

Because Expression once generated and compiled is used like it was written by you, starting from the second time method is used with the same `T`, it has the same performance as if you’d write the logic by yourself. That’s why CloneExtensions is definitely faster then reflection-based solutions and is faster then serialization-based solutions when you clone more then just a couple instances of the same time.

Take a look at CloneExtensions and feel free to provide feedback to both existing solution and plans for future developments.