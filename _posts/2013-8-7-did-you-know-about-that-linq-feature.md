---
layout: post
title: Did you know about that LINQ feature? I guess you didn’t!
excerpt_separator: <!--more-->
---

First of all, I have to say *thank you!* [Toto](http://stackoverflow.com/users/2071634/toto) for [Most optimized use of multiple Where statements](http://stackoverflow.com/q/18080998/1163867) StackOverflow question and hatchet for really great answer, which made me write this blog post.

The question is simple: **does LINQ optimize multiple Where calls?** I think most people would say no. I did say no too! Google says no - unless you dig really deep! But what is the correct answer to that question?

<!--more-->

Simple IL digging says no as well:

```
var input = new List();

var output = input.Where(x => x.StartsWith("test"))
                  .Where(x => x.Length > 10)
                  .Where(x => !x.EndsWith("test"));
```

It generates following intermidiate language instructions:

```
IL_0000: newobj instance void class [mscorlib]System.Collections.Generic.List`1::.ctor()
IL_0005: stloc.0
IL_0006: ldloc.0
IL_0007: ldsfld class [mscorlib]System.Func`2 ConsoleApplication2.Program::'CS$<>9__CachedAnonymousMethodDelegate3'
IL_000c: brtrue.s IL_001f

IL_000e: ldnull
IL_000f: ldftn bool ConsoleApplication2.Program::'b__0'(string)
IL_0015: newobj instance void class [mscorlib]System.Func`2::.ctor(object, native int)
IL_001a: stsfld class [mscorlib]System.Func`2 ConsoleApplication2.Program::'CS$<>9__CachedAnonymousMethodDelegate3'

IL_001f: ldsfld class [mscorlib]System.Func`2 ConsoleApplication2.Program::'CS$<>9__CachedAnonymousMethodDelegate3'
IL_0024: call class [mscorlib]System.Collections.Generic.IEnumerable`1<!!0> [System.Core]System.Linq.Enumerable::Where(class [mscorlib]System.Collections.Generic.IEnumerable`1<!!0>, class [mscorlib]System.Func`2<!!0, bool>)
IL_0029: ldsfld class [mscorlib]System.Func`2 ConsoleApplication2.Program::'CS$<>9__CachedAnonymousMethodDelegate4'
IL_002e: brtrue.s IL_0041

IL_0030: ldnull
IL_0031: ldftn bool ConsoleApplication2.Program::'b__1'(string)
IL_0037: newobj instance void class [mscorlib]System.Func`2::.ctor(object, native int)
IL_003c: stsfld class [mscorlib]System.Func`2 ConsoleApplication2.Program::'CS$<>9__CachedAnonymousMethodDelegate4'

IL_0041: ldsfld class [mscorlib]System.Func`2 ConsoleApplication2.Program::'CS$<>9__CachedAnonymousMethodDelegate4'
IL_0046: call class [mscorlib]System.Collections.Generic.IEnumerable`1<!!0> [System.Core]System.Linq.Enumerable::Where(class [mscorlib]System.Collections.Generic.IEnumerable`1<!!0>, class [mscorlib]System.Func`2<!!0, bool>)
IL_004b: ldsfld class [mscorlib]System.Func`2 ConsoleApplication2.Program::'CS$<>9__CachedAnonymousMethodDelegate5'
IL_0050: brtrue.s IL_0063

IL_0052: ldnull
IL_0053: ldftn bool ConsoleApplication2.Program::'b__2'(string)
IL_0059: newobj instance void class [mscorlib]System.Func`2::.ctor(object, native int)
IL_005e: stsfld class [mscorlib]System.Func`2 ConsoleApplication2.Program::'CS$<>9__CachedAnonymousMethodDelegate5'

IL_0063: ldsfld class [mscorlib]System.Func`2 ConsoleApplication2.Program::'CS$<>9__CachedAnonymousMethodDelegate5'
IL_0068: call class [mscorlib]System.Collections.Generic.IEnumerable`1<!!0> [System.Core]System.Linq.Enumerable::Where(class [mscorlib]System.Collections.Generic.IEnumerable`1<!!0>, class [mscorlib]System.Func`2<!!0, bool>)
IL_006d: pop
IL_006e: ret
```

It’s clear: they are three `Enumerable.Where()` method calls there. However, **the magic is hidden inside!** It’s not documented on MSDN at all, so you have to look into .NET Framework source code to understand what’s really happening here.

The most important thing is really the mysterious class called `WhereEnumerableIterator`. Why is it that important? Because that’s what you really get when calling `IEnumerable.Where()`.

```
public static IEnumerable Where(this IEnumerable source, Func predicate)
{
    // (...)

    return new Enumerable.WhereEnumerableIterator(source, predicate);
```

So we have to change our question. It’s now: **How is `WhereEnumerableIterator.Where()` implemented?** And here we go. The magic happens here!

```
public override IEnumerable Where(Func predicate)
{
    return new Enumerable.WhereEnumerableIterator(this.source, Enumerable.CombinePredicates(this.predicate, predicate));
}
```

As you can see, there is no iteration here, no foreach loop or anything like that. **The only thing that really happens here is the predicate combination!** Quite clever, isn’t it? So let’s reconsider chaining call from the first example.

```
var output = input.Where(x => x.StartsWith("test"))
                  .Where(x => x.Length > 10)
                  .Where(x => !x.EndsWith("test"));
```

At first glance, it seems to iterate over entire input collection with first predicate, then over that results with the second one and after that the third iteration should happen. What really happens here is:

```
foreach(string item in input)
{
    if(item.StartsWith("test") && item.Length > 10 && !item.EndsWith("test"))
        yield return item;
}
```

Just one iteration over source collection, all predicates combined into one! The same thing is done for chained Select calls, using `WhereSelectEnumerableIterator`. The optimization goes even further: there are separated implementation for `Array` and `List`: `WhereArrayIterator`, `WhereListIterator`, `WhereSelectArrayIterator` and `WhereSelectListIterator`.

```
if (source is TSource[])
    {
        return new Enumerable.WhereArrayIterator((TSource[])source, predicate);
    }
    if (source is List)
    {
        return new Enumerable.WhereListIterator((List)source, predicate);
    }
```

I have to say, it’s **quite an impressive example of attention to the details!**

Someone could say, in real life it does not really matter. I would say, that code like that makes me feel pretty confident about other parts of .NET Framework. Maybe I’m too naive to make such conclusions, but…