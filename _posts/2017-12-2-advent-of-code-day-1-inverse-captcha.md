---
layout: post
title: Advent of Code 2017 - Day 1 - Inverse Captcha
excerpt_separator: <!--more-->
---

If you've never heard of [Advent of Code](http://adventofcode.com/2017/about) you should probably check it out.
I could try to explain what it is but it's easier to just quote what [*Eric Wastl*](http://was.tl/), the organizer wrote about it:

> **Advent of Code** is a series of small programming puzzles for a variety of skill levels. They are self-contained and are just as appropriate for an expert who wants to stay sharp as they are for a beginner who is just learning to code. Each puzzle calls upon different skills and has two parts that build on a theme.

I had spare couple hours this weekend and decided to give it a go.
But it would be very boring if I was just trying to get the right answers.
Instead, I'm using it as an opportunity to get more hands-on experience with F# - something I wanted to do for a long time now but never had a chance.
I'm not planning to solve every single puzzle there is, but for the ones I do and find interesting I'm going to post a blog post with my approach.
Here comes a little bit about how I solved the first puzzle - [**Inverse Captcha**](http://adventofcode.com/2017/day/1).

<!--more-->

The problem is quite simple - given a set of digits sum all of the digits where the next digit matches the current one.

First of all, it's easier to copy/paste the input as string, so let's declare a function which takes a string and as a first thing it transforms it into an array of numbers:

```fsharp
let inverseCaptcha (input: string) =
    let arrayOfDigits = input |> Seq.map (fun c -> (int c) - 48) |> Seq.toArray
```

Now, I'm trying to go functional, so no mutable state or anything like that.
The very first function I can think of is one that when given two numbers compares them and returns the value (if they match) or `0` (if they don't).

```fsharp
    let getValueForPair a b =
        if a = b then b else 0
```

We also need a way to iterate through the collection.
In Functional Programming the idiomatic way to do it is by using recursion.
It can take the array and current index + some accumulator for intermediate results and based on stop condition will either return final value or recursively call itself with next index and new accumulated value.

In our function the stop condition is met when we reached the last element of the array.
In that case instead of calling back to the same method we want to compare current value with first element of the array, add the result to accumulated value and return.

Here's how all that can be expressed in F#:

```fsharp
    let rec inverseCaptchaIter (input: int array) (index: int) (acc: int) : int =
        if input.Length = index + 1 then
            acc + getValueForPair input.[index] input.[0]
        else
            let nextIndex = index + 1
            let newAcc = acc + getValueForPair input.[index] input.[nextIndex]
            inverseCaptchaIter input nextIndex newAcc
```

As you can see, there is no `for` or `while` loops, which are how you'd do it when writing the solution imperative way.

With that all that's left if the initial call to this recursive function, with both `index` and `acc` set to `0`.
The entire solution is not that long:

```fsharp
let inverseCaptcha (input: string) =
    let arrayOfDigits = input |> Seq.map (fun c -> (int c) - 48) |> Seq.toArray

    let getValueForPair a b =
        if a = b then b else 0
    
    let rec inverseCaptchaIter (input: int array) (index: int) (acc: int) : int =
        if input.Length = index + 1 then
            acc + getValueForPair input.[index] input.[0]
        else
            let nextIndex = index + 1
            let newAcc = acc + getValueForPair input.[index] input.[nextIndex]
            inverseCaptchaIter input nextIndex newAcc

    inverseCaptchaIter arrayOfDigits 0 0
```

It can be tested in F# Interactive using provided sample input/output pairs:

```fsharp
> inverseCaptcha "1122";;
val it : int = 3
> inverseCaptcha "1111";;
val it : int = 4
> inverseCaptcha "1234";;
val it : int = 0
> inverseCaptcha "91212129";;
val it : int = 9
```

This simple solution works perfectly for the first part of the puzzle.
The second part modifies the problem just a little bit.
Instead of comparing the value with the next element in the array we have to compare it with element that's halfway around the circular list.
The instructions explain that a bit more clearly:

> That is, if your list contains 10 items, only include a digit in your sum if the digit 10/2 = 5 steps forward matches it. Fortunately, your list has an even number of elements.

That doesn't seem like a big change, and it's not.
But instead of slightly modifying the code to fulfill that new requirement I decided to rework it and allow the caller to pass in a function which defines how the element to be compared with is selected.

That parameter will be called `getIndexToCompare` and we will provide it with `compareWithNextValue` or `compareWithValueHalfWayAway` based on which part of the puzzle we're solving:

```fsharp
let compareWithNextValue (input: (int array)) (index: int) : int  =
    (index + 1) % input.Length

let compareWithValueHalfWayAway (input: (int array)) (index: int) : int  =
    (index + (input.Length / 2)) % input.Length
```

Now we have to make `inverseCaptcha` function allow for that parameter to be passed in.

```fsharp
let inverseCaptcha getIndexToCompare (input: string) =
```

The implementation of `inverseCaptchaIter` recursive function is not that much different:

```fsharp
    let rec inverseCaptchaIter (input: int array) (index: int) (acc: int) : int =
        let indexToCompare = getIndexToCompare input index
        let currentValue = input.[index];
        let valueToCompare = input.[indexToCompare]
        let newAcc = acc + (getValueForPair currentValue valueToCompare)

        if input.Length = index + 1 then
            newAcc
        else
            inverseCaptchaIter input (index + 1) newAcc

    inverseCaptchaIter arrayOfDigits 0 0
```

You can see that instead of always going for `index + 1` or `0` `getIndexToCompare` is used to calculate the index of value to compare with.
I decided to declare a set of local variables to hold current index and value as well as index and value we're comparing to, to make it more clear what's happening there.

F# allows for partial applications, which means we can provide the first N parameters to a function and we're going to get back a function which takes the remaining parameters.
In our example we can provide `getIndexToCompare` to `inverseCaptcha` and get back a function which takes a `string`.
This way we don't have to provide `getIndexToCompare` every time.

```fsharp
let inverseCaptchaNextValue = inverseCaptcha compareWithNextValue
let inverseCaptchaValueHalfWayAway = inverseCaptcha compareWithValueHalfWayAway
```

We can validate that the code works using examples provided in the puzzle.

```fsharp
> inverseCaptchaNextValue "1122";;
val it : int = 3
> inverseCaptchaNextValue "1111";;
val it : int = 4
> inverseCaptchaNextValue "1234";;
val it : int = 0
> inverseCaptchaNextValue "91212129";;
val it : int = 9
```

```fsharp
> inverseCaptchaValueHalfWayAway "1212";;
val it : int = 6
> inverseCaptchaValueHalfWayAway "1221";;
val it : int = 0
> inverseCaptchaValueHalfWayAway "123425";;
val it : int = 4
> inverseCaptchaValueHalfWayAway "123123";;
val it : int = 12
> inverseCaptchaValueHalfWayAway "12131415";;
val it : int = 4
```

You can find the final code on GitHub: [InverseCaptcha.fsx](https://github.com/MarcinJuraszek/AdventOfCode2017/blob/master/day1/InverseCaptcha.fsx).
Let me know if you have ideas on how to improve the solution.
I'm definitely not great with F#, so there is most likely something that I'm doing wrong, or just not in the best way possible.