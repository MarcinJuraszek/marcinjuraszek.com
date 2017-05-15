---
layout: post
title: Playing around with List&lt;T&gt;, part four - trimming the underlying array size
excerpt_separator: <!--more-->
---

The last part of the series was all about increasing underlying array size. This time, I’ll try to investigate something slightly different. Question is simple: **Is the underlying array shrunk when you remove elements from the list?** Let’s find that out!

<!--more-->

To do that, we have to look for all possible ways you can remove elements from `List<T>`. Actually, there are only few of them:

```csharp
public void Clear()
public bool Remove(T item)
public int RemoveAll(Predicate<T> match)
public void RemoveAt(int index)
public void RemoveRange(int index, int count)
```

I don’t want to just copy-past code from all these methods, but I’m afraid I have no choice :) And that’s because **all these methods are really straight forward**. Starting from the easiest one:

```csharp
public void Clear()
{
    if (this._size > 0)
    {
        Array.Clear(this._items, 0, this._size);
        this._size = 0;
    }
    this._version++;
}
```

As you can see it’s really simple. It doesn’t do anything more then just calling `Array.Clear()` and setting necessary fields values. Does it change the array size? No! I have to say, that’s interesting. I would expect it to do so. But maybe there is a reason why it doesn’t (feel free to drop a comment if you know one).

Going further to `Remove()`, `RemoveAt()` and `RemoveRange()`:

```csharp
public bool Remove(T item)
{
    int num = this.IndexOf(item);
    if (num >= 0)
    {
        this.RemoveAt(num);
        return true;
    }
    return false;
}

public void RemoveAt(int index)
{
    // parameter checks removed

    this._size--;
    if (index < this._size)
    {
        Array.Copy(this._items, index + 1, this._items, index, this._size - index);
    }
    this._items[this._size] = default(T);
    this._version++;
}

public void RemoveRange(int index, int count)
{
    // parameters checks removed

    if (count > 0)
    {
        this._size -= count;
        if (index < this._size)
        {
            Array.Copy(this._items, index + count, this._items, index, this._size - index);
        }
        Array.Clear(this._items, this._size, count);
        this._version++;
    }
}
```

I feel they should be discussed together, because one uses the other internally and the third one is really just a slightly changed version of the previous. As you can see, `Remove` is actually a shortcut for `IndexOf` and `RemoveAt`. The actual work done by the second one performs bulk-copy of the rest of the array to overwrite removed item. Array size does not change at all here either. The same thing happens within `RemoveRange`. The only differences are the indexes parameters used with `Array.Copy` method.

Last but not least (and also most interesting one): `RemoveAll()`:

```csharp
public int RemoveAll(Predicate<T> match)
{
    // parameters checks removed

    int num = 0;
    while (num < this._size && !match(this._items[num]))
    {
        num++;
    }
    if (num >= this._size)
    {
        return 0;
    }
    int i = num + 1;
    while (i < this._size)
    {
        while (i < this._size && match(this._items[i]))
        {
            i++;
        }
        if (i < this._size)
        {
            this._items[num++] = this._items[i++];
        }
    }
    Array.Clear(this._items, num, this._size - num);
    int result = this._size - num;
    this._size = num;
    this._version++;
    return result;
}
```

As you can see, it's a little bit more complicated, but if you dig into it it's really quite logical. It uses two pointers to track last index (`num`) for already checked part of the array and one (`i`) for these actually being checked. Every time `_items[i]` matches the predicate we just skip that element. But when there is no match we are copying it into to `_items[num++]` to save in the array. At the end of the method unused part of the array is set to `default(T)` using `Array.Clear()` method. However, it's not being resized to match new list content.

As you can see, non of the methods changes underlying array size. It means, you can still have really huge amount of memory allocated even if the list contains only few elements. Is there any way to force the array size change? Yes, and No... Yes, because there is a `TrimExcess` method, which seems to do that. And No, because it actually don't always do that!

```csharp
public void TrimExcess()
{
    int num = (int)((double)this._items.Length * 0.9);
    if (this._size < num)
    {
        this.Capacity = this._size;
    }
}
```

As you can see, there is a threshold value set to 0.9 which makes your call effective only when there is more then 10% unused space allocated under the hoods of your list instance. MSDN states

> "This avoids incurring a large reallocation cost for a relatively small gain".

Seems reasonable, but I would probably like to see an optional bool parameter which turns on/off that feature when you're really not afraid of time performance but you have to deal with really small amount of memory.