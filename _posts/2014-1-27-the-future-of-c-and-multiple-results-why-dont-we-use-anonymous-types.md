---
layout: post
title: The Future of C# and multiple results. Why don’t we use anonymous types?
excerpt_separator: <!--more-->
---

I just watched **[The Future of C#](http://vimeo.com/84677184)** talk by Mads Torgersen recorded at NDC London conference over a month ago. Among all the stuff Mads talked about one really drawn my attention: **methods/properties with multiple results**. Unfortunately, instead of providing some new, crazy idea how to make it possible in C# he focused on making current usage easier. I think language designers could go much further and create real multiple results experience!

<!--more-->

Mads showed couple ways to workaround lack of multiple results functionality in C#. To make it easy consider following class:

```csharp
public class Point
{
    public int X { get; set; }
    public int Y { get; set; }
}
```

Now, we need to extend the `Point` class with additional functionality: `GetCoordinates()` method which returns both X and Y.

How could it be done using C# we know now? There are couple ways:

#### 1. Using Tuple class 

```csharp
public Tuple<int, int> GetCoordinates()
{
    return Tuple.Create(X, Y);
}
```

Looks nice, but has disadvantages. The main one: you don’t get meaningful names for X and Y anymore. They are `Item1` and `Item2` now.

#### 2. Additional custom class

Another common way to solve that issue is to make another, transportation class which does not have any other meaning at all. It’s only responsible for transporting values between methods:

```csharp
public class Coordinates
{
    // (...)
}
```
```csharp
public Coordinates GetCoordinates()
{
    return new Coordinates(X, Y);
}
```

Why isn’t it really happy path? You have to create and maintain separate class which actually does anything but behaves as value container.

#### 3. out parameters

This one is used by BCL quite often, e.g. for all `TryParse` methods on primitive types.

```csharp
public void GetCoordinates(out int x, out int y)
{
    x = X;
    y = X;
}
```

Even if the method itself looks nice and clear calling that kind of method is not that simple and clean. You have to declare all variables before calling the method:

```csharp
int x, y;
point.GetCoordinates(out x, out y);
```

You also cannot use `var` to make these variables implicitly types, because they are not initialized when declared. Consider how painful would it be, if it was `IDictionary<string, IEnumerable<Tuple<int, double, Stream, MyGenericClass<foo>>>>` instead of int :)

The feature Mads describe is all about 3rd option. ***What if C# would allow you to declare the variable within the method call?*** Something like

```csharp
point.GetCoordinates(out var x, out var y);
```

I have to say that: **it looks really useful!** But I think we can do more! Instead of fixing `out` parameters why don’t we introduce real multiple results syntax to C#? The easiest way to do that would be using anonymous types. I dream about something like

```csharp
public { int X, int Y } Coordinates()
{
    return new { X, Y }
}
```

It have many advantages. You got tuple-like solution, with meaningful property names, implicit typing when calling the method and no pain with `out` stuff. **And it really should not be hard to implement!** Why? Because it does not require CLR support and because **we already have anonymous types**, and what even more important their implementation is shared within assembly as long as number of parameters, their types and names match. That’s why you can do something like that:

```csharp
var x = new { Title = "myX", Value = 10 };
var y = new { Title = "myY", Value = -10 };

var array = new[] { x, y };
```

Both `x` and `y` are really instances of the same anonymous class, and that’s why you’re able to create an array of that type! The only thing that would be required is to make these types `public` instead of `internal`. But even as `public` they could (and maybe even should) be hidden from developers using e.g. special attribute.

I know that’s only my wishful thinking, but I hope someday syntax like the one described above will come true. I really look forward to project Roslyn being released as default C# compiler, because introducing that kind of features will be much easier, cheaper and because of that more likely to happen.