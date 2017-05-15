---
layout: post
title: Playing around with List&lt;T&gt;, part two - IEnumerable and IEnumerable&lt;T&gt; implementation
excerpt_separator: <!--more-->
---

After a while I finally found some time to write another post about `List<T>` internals. This time it’s all about enumeration, so I’m going to go through both non-generic `IEnumerable` and generic `IEnumerable<T>` interfaces implementation.

<!--more-->

It may be a little bit surprising, but there are actually three `GetEnumerator()` methods within `List<T>` class. That’s because both `IEnumerable.GetEnumerator(` and `IEnumerable<T>.GetEnumerator()` methods are implemented [explicitly](http://msdn.microsoft.com/en-us/library/vstudio/ms173157.aspx) (and there is another one, not connected to any of the interfaces):

```csharp
public List<T>.Enumerator GetEnumerator()
{
    return new List<T>.Enumerator(this);
}

IEnumerator<T> IEnumerable<T>.GetEnumerator()
{
    return new List<T>.Enumerator(this);
}

IEnumerator IEnumerable.GetEnumerator()
{
    return new List<T>.Enumerator(this);
}
```

As you can see, they all have exactly the same content. They differ only on the return type. Why is it made this way? To avoid boxing and unboxing. `List<T>.Enumerator` is a struct, so it would have to be boxed every time it’s returned as `IEnumerator` or `IEnumerator<T>`. It makes the foreach loop faster (it’s possible because `foreach` loop actually does not use any interface constraint on the loop source. You can create a class which would work with `foreach` without implementing neither `IEnumerable` nor `IEnumerable<T>` – but that’s a topic for another blog post).

As you may already notice, the real enumeration happens in internal type named `List<T>.Enumerator`.

```csharp
public struct Enumerator : IEnumerator<T>, IDisposable, IEnumerator
```

It has to implement both `IEnumerator` and `IEnumerator<T>` because of method above. Sounds easy, but it gives us a lot more responsibilities to remember about: all properties and methods we have to implement because of these interfaces. The most important are `Current` property and `MoveNext()` method. They are used to perform the enumerator. How are they implemented? 

```csharp
internal Enumerator(List<T> list)
{
    this.list = list;
    this.index = 0;
    this.version = list._version;
    this.current = default(T);
}

public T Current
{
    get { return this.current; }
}

public bool MoveNext()
{
    List<T> list = this.list;
    if (this.version == list._version && this.index < list._size)
    {
        this.current = list._items[this.index];
        this.index++;
        return true;
    }
    return this.MoveNextRare();
}
```

For now, just skip `version` and `MoveNextRare()` usages. Everything important is done using the underlying `T[]` array. There is an indexer pointing to currently active element from the array. Every time `MoveNext()` is called the `index` is incremented, new active value is copied to local field (to save array lookups) and then every time `Current` property value is requested the copied value is returned. Of course, everything starts with `index` set to 0 and `Current` set to `default(T)`. May sound a little complicated but is really simple.

There is also an explicit `IEnumerator.Current` implementation:

```csharp
object IEnumerator.Current
{
    get
    {
        if (this.index == 0 || this.index == this.list._size + 1)
        {
            ThrowHelper.ThrowInvalidOperationException(ExceptionResource.InvalidOperation_EnumOpCantHappen);
        }
        return this.Current;
    }
}
```

How it differs? It throws exceptions, when you try use `Current` property before first `MoveNext()` call or when you've already got all items (`MoveNext()` call returned `false`). Why is it done this way? I have not idea.

Moving to `version` and `MoveNextRare()`, there is one more important thing, which is actually more general and connected to the nature or enumerators themselves, which force following rule (copied from MSDN):

> An enumerator remains valid as long as the collection remains unchanged. If changes are made to the collection, such as adding, modifying, or deleting elements, the enumerator is irrecoverably invalidated and its behavior is undefined.

You can't modify the collection while enumerating it. Every change made to the source collection has to invalidate the enumerator. Sounds quite important, doesn't it? How does `List<T>.Enumerator` makes it happen? The idea is really simple. It uses a counter on `List<T>` class, which is incremented every time collection is changed. When you create an enumerator, the current collection version (that's how the field is named) is copied, and every time you're trying to use the enumerator the version of enumerator and source collection are compared. They are not equal? Collection changed, exception is being thrown, end of the story. 

Really simple, isn't it? It's even simple to read from code then from description:

```csharp
private bool MoveNextRare()
{
    if (this.version != this.list._version)
    {
        ThrowHelper.ThrowInvalidOperationException(ExceptionResource.InvalidOperation_EnumFailedVersion);
    }
    this.index = this.list._size + 1;
    this.current = default(T);
    return false;
}
```

`List<T>._version` field is initialized with 0 on the constructor and is updated by every method that really changed the collection: `Add`, `Clear`, `Insert`, `InsertRange`, `RemoveAll`, `RemoveAt`, `RemoveRange`, `Reverse`, `Sort` and indexing property setter. The setter example:

```csharp
public T this[int index]
{
    get
    {
        // (...)
    }
    set
    {
        if (index >= this._size)
        {
            ThrowHelper.ThrowArgumentOutOfRangeException();
        }
        this._items[index] = value;
        this._version++;
    }
}
```

Another interesting detail: Both `IEnumerator` and `IEnumerator<T>` define `Reset()` method, which should bring enumerator to it's default, initial state. However, as you can find on MSDN you shouldn't rely on the method at all:

> The `Reset` method is provided for COM interoperability. It does not necessarily need to be implemented; instead, the implementer can simply throw a `NotSupportedException`.

Looks like that's why the method is implemented explicitly, so you can't use it without casting the enumerator to one of the interfaces.

```csharp
void IEnumerator.Reset()
{
    if (this.version != this.list._version)
    {
        ThrowHelper.ThrowInvalidOperationException(ExceptionResource.InvalidOperation_EnumFailedVersion);
    }
    this.index = 0;
    this.current = default(T);
}
```

At the end, I'd like to answer the question, why the fact that `List<T>.Enumerator` is a struct really matters. Consider following code:

```csharp
var list = new List<int>(1) { 3 };
using (var e = list.GetEnumerator())
{
    Console.WriteLine(e.MoveNext());
    Console.WriteLine(e.Current);

    ((IEnumerator)e).Reset();

    Console.WriteLine(e.MoveNext());
    Console.WriteLine(e.Current);
}
```

How do you think, what is the output? Is it true 3 true 3? If you think so, you're wrong! Because `List<T>.Enumerator` is a value type, every time you cast it to either `IEnumerator` or `IEnumerator` it's being boxed, what means you're actually creating a copy of the enumerator! That's why the code above prints true 3 false 0. I don't think you'll face similar problem in real-case scenario, but it's good to know, that calling `GetEnumerator` on `List<T>` you're getting a struct, not a class.

As you can see, even so apparently trivial case like returning all list items one after another can be tricky. Next time on the series I'm going to examine the underlying array size updating process. There will be a nice time vs. memory performance issue to consider: is it better to have less unused space reserved or to make the operations run faster? I don't have the answer yet and hope `List<T>` will give me one.