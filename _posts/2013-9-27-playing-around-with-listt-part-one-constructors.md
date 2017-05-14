---
layout: post
title: Playing around with List<T>, part one: Constructors
excerpt_separator: <!--more-->
---

`List<T>` is one of the most commonly used types from .NET Framework Base Class Library. Although it is used so often not everyone is really familiar with how the class works internally. Almost everyone knows that `List<T>` uses `T[]` array internally to store the items. But for most people that’s the only internal detail they know. In next few blog post I’ll try to step through `List<T>` source code and point some interesting implementation details that every .NET developer should be aware of.

<!--more-->

Starting from the basics, I’d like to dive deep into `List<T>` class constructors first. There are three instance constructors available:

```
public List()
public List(int capacity)
public List(IEnumerable<T> collection)
```

As I mentioned before `List<T>` uses an array to store collection elements. The array size is automatically updated when needed. But what is the initial size of the array? Well, it depends on which constructor is being used to initialize the `List<T>` class instance.

The parameterless `List<T>` constructor sets the underlying array to `T[0]`. To make it even faster the `T[0]` instance is stored internally in static, read only field:

```
private static readonly T[] _emptyArray = new T[0];

public List()
{
    this._items = List<T>._emptyArray;
}
```

Moving to next constructor, the one with an `int` parameter. As you could guess, the `capacity` parameter value is used to determine underlying array size. There are only two special cases: exception is being thrown when initial capacity is lower than zero and `_emptyArray` is used again, when capacity equals 0.

```
public List(int capacity)
{
    if (capacity < 0)
    {
        ThrowHelper.ThrowArgumentOutOfRangeException(ExceptionArgument.capacity, ExceptionResource.ArgumentOutOfRange_NeedNonNegNum);
    }
    if (capacity == 0)
    {
        this._items = List<T>._emptyArray;
        return;
    }
    this._items = new T[capacity];
}
```

It is not really interesting, is it? The real magic I’d like to write about is hidden under the last constructor. It takes a collection of elements as `IEnumerable<T>` and uses the items to prepare initial state of the `List<T>`. Sounds quite easy, so you may wonder what magic can be done to solve the problem. The easiest solution could be:

1. Create new, empty `List<T>`
2. Iterate over source collection and call `Add` method for each item

Problem solved, right? Yes, and no. Yes, because it works just fine. No, because it can be done much better. And actually, it is done much better in BCL.
The main problem with approach described above is need to change size of underlying array while adding elements. You can’t set the initial capacity, because `IEnumerable<T>` does not expose Count property. But wait, `ICollection<T>` does! And because `ICollection<T>` inherits from `IEnumerable<T>` it’s quite likely that collection implements both `ICollection<T>` and `IEnumerable<T>`. Why shouldn’t we give it a try and check, if object passed as the collection parameter follows the same pattern? That’s exactly what happens when you use the third `List<T>` constructor.

```
public List(IEnumerable<T> collection)
{
    if (collection == null)
    {
        ThrowHelper.ThrowArgumentNullException(ExceptionArgument.collection);
    }

    ICollection<T> collection2 = collection as ICollection<T>;
    if (collection2 != null)
    {
        int count = collection2.Count;
        if (count != 0)
        {
            this._items = new T[count];
            collection2.CopyTo(this._items, 0);
            this._size = count;
        }
        else
        {
            this._items = List<T>._emptyArray;
            return;
        }
    }
    else
    {
        this._size = 0;
        this._items = List<T>._emptyArray;
        using (IEnumerator<T> enumerator = collection.GetEnumerator())
        {
            while (enumerator.MoveNext())
            {
                this.Add(enumerator.Current);
            }
        }
    }
}
```

As you can see, the code uses a fact that collection implements `ICollection<T>` to copy all elements at once using` ICollection<T>.CopyTo` method. This approach should be much faster then copying elements one by one. Sounds great in theory, but is it really true in practice? It depends on how source collection class implements `CopyTo` method. For `List<T>` the underlying array is being copied directly, so it is extremely fast. That’s why for following code creating listTwo won’t take long, even if it contains a lot of elements:

```
// create list of integers, from 0 to 100.000.000
List<int> listOne = Enumerable.Range(0, 100000000).ToList();
// make a copy of listOne using List(IEnumerable<T> collection) constructor
List<int> listTwo = new List<int>(listOne);
```

This `List<T>` constructor feature is not documented at all at MSDN. It is also declared as O(n) operation, which is true for worst case, but is not for the best one, which is O(1).

Another question is: can I do any better then the constructor does internally? Actually, you can’t. You don’t have direct access to underlying array, so you can’t just copy list content there. Even using the constructor with initial capacity specified and calling `AddRange()` method on that list will not be as fast as using the constructor with collection as a parameter (of course, as long as it implements `ICollection<T>`).

To sum up, even so trivial case like creating new object instance hides some examples of great attention to details. Every time you create new `List<T>` you should consider which constructor to use to make the process as fast as possible. Do you know (or at least approximate) how many elements will be held in the list? If yes, specify the list initial capacity to save on underlying array updates. Do you create new `List<T>` from existing collection? Don’t try to be smarter and just use proper constructor. It will take care of optimizations for you! You can save a lot with taking the correct approach here.

Next time I’d try to examine the way `List<T>` implements `IEnumerable` and `IEnumerable<T>` interfaces.