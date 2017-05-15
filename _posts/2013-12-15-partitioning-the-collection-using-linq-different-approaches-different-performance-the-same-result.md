---
layout: post
title: Partitioning the collection using LINQ - different approaches, different performance, the same result
excerpt_separator: <!--more-->
---

Another blog post inspired by a [StackOverflow question](http://stackoverflow.com/q/20556678/1163867). This time it’s all about LINQ, performance and a tiny little detail, that really matters. The question itself is about `yield` keyword in VB.NET, but there is another, much more interesting part I’d like to examine. The algorithm quoted in the question is the key.

<!--more-->

The idea is simple. **How to partition a collection into parts with given number of elements in ever part?** Algorithm presented in the question is as easy as the questions seems to be:

```csharp
public IEnumerable<IEnumerable<T>> Partition<T>(IEnumerable<T> source, int size)
{
    if (source == null)
        throw new ArgumentNullException("list");

    if (size < 1)
        throw new ArgumentOutOfRangeException("size");

    int index = 1;
    IEnumerable<T> partition = source.Take(size).AsEnumerable();

    while (partition.Any())
    {
        yield return partition;
        partition = source.Skip(index++ * size).Take(size).AsEnumerable();
    }
}
```

Question is, is the algorithm good and efficient? It returns correct results, that’s for sure. But that’s not the only important part of every algorithm. Unfortunately, I must say that **the algorithm is no good**. To answer why it’s no a good algorithm? I’d like to show you another approach on solving the same problem:

```csharp
public IEnumerable<IEnumerable<T>> Partition<T>(IEnumerable<T> source, int size)
{
    var partition = new List<T>(size);
    var counter = 0;

    using (var enumerator = source.GetEnumerator())
    {
        while (enumerator.MoveNext())
        {
            partition.Add(enumerator.Current);
            counter++;
            if (counter % size == 0)
            {
                yield return partition.ToList();
                partition.Clear();
                counter = 0;
            }
        }

        if (counter != 0)
            yield return partition;
    }
}
```

Is has exactly the same signature and returns exactly the same results. **Why is it better then?** There are couple possible answers:

- because it does no use `Skip`/`Take` methods
- because it has *O(n)* complexity, when the other one is *O(n*log(n))*
- because it iterate over entire collection only once, and the other one does it multiple times

If you look closer, all these actually means the same: **the second method is much faster!** How much? A lot :) Look at the charts. They show execution time depending on number of partitions that need to be created. Source collections have 1000000 elements and they are created using following code:

```csharp
var enumSource = Enumerable.Range(0, size);
var arraySource = enumSource.ToArray();
var listSource = arraySource.ToList();
```

You may wonder why I tried the same algorithm on three different collections. That’s because of how `Skip`/`Take` solution works: it iterates from that beginning of collection every time new partition is requested. It may not be important if your source is static collection (like `Array` or `List`), but it will cause `Enumerable.Range` to generate the collection every time again and again. That’s really not necessary, is it?
 
Y-axis shows execution time and X-axis shows number of partitions that are being generated. **The difference is huge**, isn’t it? It takes about 6 second to generate 1000 partitions using Skip/Take algorithm and about 40ms to do that with the other one!

I’m writing this post to highlight that if LINQ seems to be really great solution for nearly every collection-related problem and you can get working solution really easily using it, it’s not always really a good and fast solution.