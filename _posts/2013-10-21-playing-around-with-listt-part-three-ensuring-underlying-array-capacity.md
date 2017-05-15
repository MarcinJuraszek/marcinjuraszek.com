---
layout: post
title: Playing around with List&lt;T&gt;, part three - Ensuring underlying array capacity
excerpt_separator: <!--more-->
---

This time on the series I’m gonna examine how `List<T>` ensures the underlying array capacity. But because it’s quite interesting topic I decided to **focus on adding new elements to the list only**, leaving deleting/clearing for the next part.

<!--more-->

First of all, we have to list all ways to add new elements into the list. There are four of them available:

```csharp
public void Add(T item)
public void AddRange(IEnumerable<T> collection)
public void Insert(int index, T item)
public void InsertRange(int index, IEnumerable<T> collection)
```

I’ve already written a little bit about `InsertRange` when writing about constructors, but they all should be quite easy to understand. Both `Add` and `AddRange` insert new data (one or more items) at the end of the list while `Insert` and `InsertRange` inserts data starting from given index. In both cases **`List<T>` class has to take care of ensuring, that underlying array can handle existing and new elements**. Because that logic has to be used from couple different methods it was separated into separated private helper method called `EnsureCapacity`.

```csharp
private void EnsureCapacity(int min)
```

Looks easy, but before we’ll check what the method actually does let’s focus on another question: **what is passed as `min` parameter value when the method is called?** An answer can be easily found. Both `Add` and `Insert` call it following given pattern:

```
this.EnsureCapacity(this._size + 1);
```

Case is even easier with `AddRange` and `InsertRange`, because the first one uses the second internally

```csharp
public void AddRange(IEnumerable<T> collection)
{
    this.InsertRange(this._size, collection);
}
```

At the end, `EnsureCapacity` is called using number of elements found in the source collection (if it can be determined without enumeration):

```csharp
int count = collection2.Count;
if (count > 0)
{
    this.EnsureCapacity(this._size + count);
```

Otherwise, to source collection is enumerated with `Insert` method call on every element.

But moving back to `EnsureCapacity`. We now know that the method gets one parameter which determines minimal capacity for underlying array. So someone could say, just use it not as minimum but as direct array size. It would have a great advantage: no unused memory space used. However, because changing array size is quite time consuming it would be really inefficient. We should make sure that underlying array reallocation happens as rarely as possible. But on the other hand we want the structure to not allocate big amount of unused memory. Quite difficult war between time and memory efficiency. How did `List<T>` solve that problem?

```csharp
private void EnsureCapacity(int min)
{
    if (this._items.Length < min)
    {
        int num = (this._items.Length == 0) ? 4 : (this._items.Length * 2);
        if (num > 2146435071)
        {
            num = 2146435071;
        }
        if (num < min)
        {
            num = min;
        }
        this.Capacity = num;
    }
}
```

It follows exponential function by multiplying current array size by 2 whenever it's possible.

Following graph represents size of unused allocated memory in correlation to number of element stored within a list in case they were all added one after another.

The graph has two really important properties:

- Always over 50% of underlying array size is really used by the list
- The bigger the list is, the less often it is necessary to reallocate underlying array

The second one is really important, because reallocating small array is much less expensive then reallocating array with hundreds or thousands of elements.

I remember a really nice StackOverflow question titled [How is the internal array of a List increased when using AddRange](http://stackoverflow.com/a/18573164/1163867). Author asked if the underlying array size is always changed to just match current list size + number of elements added. Answer is: it's not. That's because even when collection implements `ICollection` it's possible that `EnsureCapacity` will just multiply underlying array size by 2 instead of setting it to strict number. The correct new size of array can be described as `Max(old_size * 2, old_size + count)` and it will vary depending on current `List<T>` size.