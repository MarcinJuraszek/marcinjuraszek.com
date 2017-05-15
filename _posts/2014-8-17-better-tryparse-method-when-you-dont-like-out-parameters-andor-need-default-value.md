---
layout: post
title: Better TryParse method, when you don’t like out parameters and/or need default value
excerpt_separator: <!--more-->
---

How many times in your code do you need to parse strings to primitive values? I would guess pretty often. How often do you use `TryParse` method, to avoid unnecessary exception handling? The same guess – probably pretty often. **How many times did you wish that `TryParse` didn’t use out method parameter?** Yes, the same answer again. But how many times did you think how to improve that scenario? Probably never. I think you should have done that! There is quite a lot of room for improvement here. Simple tricks that may make your parsing logic much simpler, cleaner and more verbatim.

<!--more-->

The main problem I have with every TryParse method from BCL is that they all use `out` parameter to return parsed value. **That’s because the return value indicated how successful the parsing was, not what is the result of that operation.** Because of that, you have to declare a variable to store result in separate line:

```
DateTime value;
DateTime.TryParse(inputString, out value);
```

With C# 6 and inline variable declarations, you’ll be able to write following:

```
DateTime.TryParse(inputString, out DateTime value);
```

But there is still one issue that is not easy to deal with: **how can I specify a default value**, which should be used when parsing fails? You have to use if statement:

```
DateTime value;
if(!DateTime.TryParse(inputString, out value))
{
    value = DateTime.Now;
}
```

This one is not possible with inline variable declaration, because value would get scoped to the scope of if statement, which would make it quite unusable:

```
if(!DateTime.TryParse(inputString, out DateTime value))
{
    value = DateTime.Now;
}

Console.WriteLine(value.ToShortDateString());   // compiler error, value is not declared!
```

Setting the default value before calling TryParse will not help either because, as [MSDN states](http://msdn.microsoft.com/en-us/library/ch92fbc1(v=vs.110).aspx), when TryParse fails to parse the string it sets result to DateTime.MinValue:

> When this method returns, contains the `DateTime` value equivalent to the date and time contained in `s`, if the conversion succeeded, or `MinValue` if the conversion failed. 

So how can you make it better? You can declare your own `TryParse` method! But how can I make it work without
`out` parameter? I suggest using `Nullable<T>` instead!

```
public static class DateTimeUtils
{ 
    public static DateTime? TryParse(string value)
    {
        DateTime result;
        if (!DateTime.TryParse(value, out result))
            return null;
        return result;
    }
}
```

Why do I think it’s better? **Let’s look how you can use it!**

```
DateTime myDateTime = DateTimeUtils.TryParse(myString) ?? DateTime.Now;
```

Much clearer, isn’t it? You can go further, and **hide default value inside utility method as well**:

```
public static DateTime TryParse(string value, DateTime defaultValue)
{
    return DateTimeUtils.TryParse(value) ?? defaultValue;
}
```

This way you don’t have to use `??` operator:

```
DateTime myDateTime = DateTimeUtils.TryParse(myString, DateTime.Now);
```

Of course, there are cases when the standard `TryParse` is better. E.g. when you need to stop further lines of code from evaluating when parsing fails

```
DateTime value;
if(!DateTime.TryParse(inputString, out value))
{
    return;
}
```

But even then you can use `Nullable<T>.HasValue` instead:

```
DateTime? value = DateTimeUtils.TryParse(inputString)
if(!value.HasValue)
{
    return;
}
```

But to be honest, in that case I would stick to .NET implementation, because when parsing succeeds, I already have `DateTime`, not `DateTime?`, which is easier to deal with.

As you see, you can make `TryParse` better, but there are certain cases when that improved version really shines. There are also cases, when old, already known version or `TryParse` makes much more sense. Having both available gives you better set of tools, and lets you use the one that is best suited for your needs. That’s exactly what great programmer should do: use the best tools possible for given job. Nobody even said that you can’t make your own tools though, so do it to make your development easier!