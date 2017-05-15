---
layout: post
title: Playing around with List&lt;T&gt;, part five - finding elements
excerpt_separator: <!--more-->
---

This time I’ll try to examine how are all search-related methods in `List<T>` implemented. Here is quite long list of all these methods:

<!--more-->

```csharp
public bool Exists(Predicate<T> match)
public T Find(Predicate<T> match)
public List<T> FindAll(Predicate<T> match)
public int FindIndex(Predicate<T> match)
public int FindIndex(int startIndex, Predicate<T> match)
public int FindIndex(int startIndex, int count, Predicate<T> match)
public T FindLast(Predicate<T> match)
public int FindLastIndex(Predicate<T> match)
public int FindLastIndex(int startIndex, Predicate<T> match)
public int FindLastIndex(int startIndex, int count, Predicate<T> match)
public int IndexOf(T item)
public int IndexOf(T item, int index)
public int IndexOf(T item, int index, int count)
public int LastIndexOf(T item)
public int LastIndexOf(T item, int index)
public int LastIndexOf(T item, int index, int count)
```

But as soon as you start looking inside the code, you can realize that most of them are implemented using other ones, either just adding some default parameter values, checking what is the return value they produce or passing the program flow to `Array.IndexOf`/`Array.LastIndexOf` methods. At the end there are just 5 methods which actually do something interesting:

```csharp
public T Find(Predicate<T> match)
public List<T> FindAll(Predicate<T> match)
public int FindIndex(int startIndex, int count, Predicate<T> match)
public T FindLast(Predicate<T> match)
public int FindLastIndex(int startIndex, int count, Predicate<T> match)
```

And as you can imagine, they all are pretty straight forward. I’m gonna list just two of them here:

```csharp
public T Find(Predicate<T> match)
{
    // parameter check skipped

    for (int i = 0; i < this._size; i++)
    {
        if (match(this._items[i]))
        {
            return this._items[i];
        }
    }
    return default(T);
}
```

```csharp
public int FindIndex(int startIndex, int count, Predicate<T> match)
{
    // parameter checks skipped

    int num = startIndex + count;
    for (int i = startIndex; i < num; i++)
    {
        if (match(this._items[i]))
        {
            return i;
        }
    }
    return -1;
}
```

I have to say that: there is nothing interesting here! `for` loop, `if` statement and that's it. `LastXXX` methods look almost exactly the same. They differ only by loop variable initial value. Even `FindAll` does almost not differ. Of course it stores all found items in `List<T>` and then returns the list, but that's not surprising at all.

As you can see, there is almost nothing to talk about here. Unfortunately, we have to get used to it, because all other methods are that simple too. But that's good, isn't it?