---
layout: post
title: Convert class, IConvertible interface and Generics – deep dive into performance
excerpt_separator: <!--more-->
---

First non LINQ-related question on my blog, but another one in response to great StackOverflow question: [Casting generic parameter to and from integer](http://stackoverflow.com/q/18182285/1163867). Every day you can find something that inspires you to do your own research and think hard why things work like they do. That’s exciting, isn’t it?

<!--more-->

Getting back to question. Author posted following code and simply asked, how can it be done better?

```csharp
class Test<T> where T : struct, IConvertible
{
    public static T TestFunction(T x)
    {
        int n = Convert.ToInt32(x);
        T result = (T)Convert.ChangeType(n, typeof(T));
        return result;
    }
}
```

But there are some assumptions that have to be made before any work can be done on the question:

- The class is only intended to work with build-in simple types, like byte, uint, etc.
- The main goal here is not to make code clean, but to make it fast.

My first thought was, let’s use [Expression Tree](http://msdn.microsoft.com/en-us/library/bb397951.aspx) to compile proper conversion code at runtime. The response I come with is:

```csharp
class Test<T> where T : struct, IConvertible
{
    private static Func<int, T> _getInt;

    static Test()
    {
        var param = Expression.Parameter(typeof(int), "x");
        UnaryExpression body = Expression.Convert(param, typeof(T));
        _getInt = Expression.Lambda<Func<int, T>>(body, param).Compile();
    }

    public static T TestFunction(T x)
    {
        int n = Convert.ToInt32(x);
        T result = _getInt(n);
        return result;
    }
}
```

It works much better then the one from question. However, I started thinking **how much better it is, and can it be done any better?** Challenging question, so let’s try to face it. Just to make the performance test results comparable, I decided to test all things against three `T` types: `byte`, `ushort`, and `uint`.

I decided to split tests in two: one part for `T` to `int` and another one for the opposite direction. Things I’ve come up with and gave them a try:

- `x.ToInt32()` instead of `Convert.ToInt32(x)`
- Expression Tree with `(int)x` to convert `T` to `int` and `(T)n` as `int` to `T` conversion.
Code for every testes conversion method can be found on [pastebin](http://pastebin.com/hX17Xn8f). Result for particular cases presented on charts below:

int to T conversion time in ms

T to int conversion time in ms

As you can see, the results are quite clear. The fastest way to convert `int `to `T` is definitely the one using Expression Tree:

```csharp
private static class TestClass<T> where T : IConvertible
{
    static Func<T, int> _getInt;
    static Func<int, T> _getT;

    static TestClass()
    {
        var param = Expression.Parameter(typeof(int), "x");
        UnaryExpression body = Expression.Convert(param, typeof(T));
        _getT = Expression.Lambda<Func<int, T>>(body, param).Compile();

        // (...)
    }

    public static int GetInt(T x)
    {
        return _getInt(x);
    }

    public static T GetT(int x)
    // (...)
}
```

However, the opposite direction conversion is faster when standard `ToInt32` method is being called:

```csharp
private static class TestClass<T> where T : IConvertible
{
    public static int GetInt(T x)
    {
        return x.ToInt32(null);
    }

    public static T GetT(int x)
    // (...)
}
```

Couple conclusions about test results:
- Convert tests take so long, because of boxing/unboxing operations from `byte`/`uint`/`ushort` to `IConvertible` interface instance.
- `T` to `int` conversion on both Convert and ExpressionTree tests do actually the same things under the hood: both use implicit conversion. However, the first one uses standard method calls when second one uses `Func` delegate call. That’s why the second one is a little bit slower.
- There is one thing, that is not measured but actually requires some work before ExpressionTest methods are called for the first time – static constructor code, which actually creates and compiles the expression trees. But because that happens only once, I decided to skip it from tests

And just to be sure: this is the first time I’ve tried to perform low-level performance tests, so any questions and concerns about the results are really welcome.