---
layout: post
title: Learning F# and solving Digit Recognizer competition on kaggle
excerpt_separator: <!--more-->
---

I’ve started learning F# couple weeks ago, but unfortunately after few days I got quite busy and after these days I still know almost exactly nothing about functional programming at all. That’s why I decided I have to look for some challenges and samples I could work on while learning. That’s how I found [F# and Machine Learning Dojo](http://www.slideshare.net/mathias-brandewinder/fsharp-and-machine-learning-dojo) slideshow and [Digit Recognizer competition](https://www.kaggle.com/c/digit-recognizer) on kaggle. I decided to give it a try. Of course, the main goal is to learn F#, not to get 100% correctness in the competition. You should have it in mind while reading the post :)

<!--more-->

First great thing about F# I really like is a fact, that you don’t have to compile/build your code. Just type it in F# Interactive window and it just works. This way **I was able to prepare working 1-nearest-neighbor classifier without hitting F5!** That’s quite awesome. So lets the fun begin.

Reading the dojo description slides you can see, that most important part of classifier is the way you compare two images. So lets face that problem first. Because F# is a functional language, you can just create function and use it later when you need it. I named that function distance because it’s quite similar to Distance Formula, which allows you to calculate distance between two points in the Cartesian Plane:

Expanding that to more than 2 coordinates for each point we get

Which can be easy translated into F# code using Array.map2 and Array.sum calls

```
> let distance P Q = Array.sum (Array.map2 (fun p q -> (p-q)*(p-q)) P Q);;

val distance : P:int [] -> Q:int [] -> int
```

I decided to skip square root, because it’s not the value what matters, but difference between distances, so square root is not important at all. But getting back to F#, as you can see, evaluating function declaration in F# Interactive window prints function parameter types. In that case, we have **a method which takes two `int[]` arrays and return an `int` value**, which is how much different the arrays are. Lets try the function and check if it works fine:

```
> distance [| 0;1;2 |] [| 4;3;2 |];;
val it : int = 20
```

20 is result of (0-4)^2 + (3-1)^2 + (2-2)^2, so seems it works just fine :)

Moving on, we can start reading our data. To property prepare training and validation data we have to do following steps:

1. Load text from csv file, and create a string[] array with a string for each line
2. Skip the first line, the header line
3. Split each line into string[] by a comma
4. Parse each string into an integer
5. Take first int as expected result (the number on image) and all other integers as list of pixels

So lets create a function for each of these points, starting from the very last one. But before that, we have to declare type to store the items.

```
> type Item = { Value:int; Pixels:int[] };;

type Item =
{Value: int;
Pixels: int [];}
```

and now the functions:

```
> let getRecord (x:int[]) = { Value = x.[0]; Pixels = x.[1..] };;

val getRecord : x:int [] -> Item

> let parseInt = Int32.Parse;;

val parseInt : arg00:string -> int

> let parseIntArray = Array.map parseInt;;

val parseIntArray : (string [] -> int [])

> let splitByComma (s:string) = s.Split([| ',' |]);;

val splitByComma : s:string -> string []

> let skipHeaderRow (s:string[]) = s.[1..];;

val skipHeaderRow : s:string [] -> string []

> let readAllLines p = File.ReadAllLines(p);;

val readAllLines : p:string -> string []
```

Everything looks pretty straightforward, doesn’t it? Now, we can combine all these functions into one, which will take a file path and return array of items.

```
>
let readItemsFromFile p =
    (readAllLines p)
    |> skipHeaderRow
    |> Array.map splitByComma
    |> Array.map parseIntArray
    |> Array.map getRecord;;

val readItemsFromFile : p:string -> Item []
```

And yes, F# compiler can easily figure out that `readItemsFromFile` takes a `string` and returns `Item[]` array :) 14 lines of code which give you really powerful functionality. That’s amazing. But don’t stop here. We should push it further and actually how good the classifier is.< Starting with loading training data 

```
> let trainingData = readItemsFromFile “C:\\trainingsample.csv”;;

val trainingData : Item [] =
[|{Value = 1;
Pixels =
[|0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; …|];};
{Value = 0;
Pixels =
[|0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; …|];};
{Value = 1;
Pixels =
[|0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; …|];};
{Value = 4;
Pixels =
[|0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; …|];};
{Value = 0;
Pixels =
[|0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; …|];};
{Value = 0;
Pixels =
[|0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; …|];};
{Value = 7;
Pixels =
[|0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; …|];};
{Value = 3;
Pixels =
[|0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; …|];};
{Value = 5;
Pixels =
[|0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; …|];};
{Value = 3;
Pixels =
[|0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0;
0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; 0; …|];};
…|]
```

Next thing we need is `getNearest` function, which will get from array of Item the one which is closest to searched one.

```
>
let getNearestItem v t =
    t
    |> Array.minBy (fun x -> distance x.Pixels v.Pixels);;

val getNearestItem : v:Item -> t:Item [] -> Item
```

Now lets do the same with validation data, but instead of just loading it, I’m going to **get the nearest `Item` from `trainingData` set too**, to make next steps easier.

```
>  type ItemWithNearest = { Value:int; Closest:int};;

type ItemWithNearest =
{Value: int;
Closest: int;}

>
let validationData =
    readItemsFromFile "c:\\validationsample.csv"
    |> Array.map (fun i -> (i, (getNearestItem i trainingData)))
    |> Array.map (fun x -> { Value = (fst x).Value; Closest = (snd x).Value });;

val validationData : ItemWithNearest [] =
[|{Value = 8;
Closest = 8;}; {Value = 7;
Closest = 7;}; {Value = 2;
Closest = 2;}; {Value = 6;
Closest = 6;};
{Value = 3;
Closest = 3;}; {Value = 1;
Closest = 1;}; {Value = 2;
Closest = 2;}; {Value = 6;
Closest = 6;};
{Value = 6;
Closest = 6;}; {Value = 6;
Closest = 6;}; {Value = 6;
Closest = 6;}; {Value = 4;
Closest = 4;};
{Value = 8;
Closest = 8;}; {Value = 1;
Closest = 1;}; {Value = 0;
Closest = 0;}; {Value = 7;
Closest = 7;};
{Value = 6;
Closest = 6;}; {Value = 2;
Closest = 2;}; {Value = 0;
Closest = 0;}; {Value = 3;
Closest = 3;};
{Value = 6;
Closest = 6;}; {Value = 6;
Closest = 6;}; {Value = 1;
Closest = 1;}; {Value = 2;
Closest = 2;};
{Value = 2;
Closest = 2;}; {Value = 1;
Closest = 1;}; {Value = 4;
Closest = 9;}; {Value = 0;
Closest = 0;};
{Value = 1;
Closest = 1;}; {Value = 7;
Closest = 7;}; {Value = 2;
Closest = 2;}; {Value = 9;
Closest = 9;};
{Value = 7;
Closest = 7;}; {Value = 7;
Closest = 7;}; {Value = 3;
Closest = 3;}; {Value = 2;
Closest = 2;};
{Value = 3;
Closest = 3;}; {Value = 0;
Closest = 0;}; {Value = 8;
Closest = 8;}; {Value = 6;
Closest = 6;};
{Value = 8;
Closest = 8;}; {Value = 9;
Closest = 9;}; {Value = 1;
Closest = 1;}; {Value = 9;
Closest = 9;};
{Value = 7;
Closest = 7;}; {Value = 3;
Closest = 3;}; {Value = 7;
Closest = 7;}; {Value = 4;
Closest = 4;};
{Value = 7;
Closest = 7;}; {Value = 4;
Closest = 9;}; {Value = 7;
Closest = 7;}; {Value = 8;
Closest = 4;};
{Value = 4;
Closest = 4;}; {Value = 3;
Closest = 3;}; {Value = 0;
Closest = 0;}; {Value = 6;
Closest = 6;};
{Value = 7;
Closest = 7;}; {Value = 4;
Closest = 4;}; {Value = 3;
Closest = 3;}; {Value = 9;
Closest = 9;};
{Value = 1;
Closest = 1;}; {Value = 5;
Closest = 5;}; {Value = 0;
Closest = 0;}; {Value = 8;
Closest = 3;};
{Value = 6;
Closest = 6;}; {Value = 2;
Closest = 2;}; {Value = 7;
Closest = 7;}; {Value = 1;
Closest = 1;};
{Value = 2;
Closest = 2;}; {Value = 3;
Closest = 3;}; {Value = 9;
Closest = 7;}; {Value = 3;
Closest = 3;};
{Value = 4;
Closest = 4;}; {Value = 0;
Closest = 0;}; {Value = 8;
Closest = 8;}; {Value = 7;
Closest = 7;};
{Value = 7;
Closest = 7;}; {Value = 0;
Closest = 0;}; {Value = 4;
Closest = 4;}; {Value = 1;
Closest = 1;};
{Value = 2;
Closest = 2;}; {Value = 1;
Closest = 1;}; {Value = 6;
Closest = 6;}; {Value = 2;
Closest = 2;};
{Value = 8;
Closest = 8;}; {Value = 4;
Closest = 4;}; {Value = 4;
Closest = 4;}; {Value = 3;
Closest = 3;};
{Value = 9;
Closest = 9;}; {Value = 1;
Closest = 1;}; {Value = 2;
Closest = 2;}; {Value = 0;
Closest = 0;};
{Value = 1;
Closest = 1;}; {Value = 4;
Closest = 4;}; {Value = 6;
Closest = 6;}; {Value = 5;
Closest = 5;};
{Value = 1;
Closest = 1;}; {Value = 4;
Closest = 9;}; {Value = 4;
Closest = 4;}; {Value = 9;
Closest = 9;}; ...|]
```

OK, we are almost there. Now we just have to count number of items with correct prediction and divide it by total number of elements, to get percentage of correct classifications.
```
>
let percentOfCorrect =
    let positive =
        validationData
        |> Array.filter (fun i -> i.Value = i.Closest)
        |> Array.length
    let total = Array.length validationData
    (double positive)/(double total);;

val percentOfCorrect : float = 0.944
```

And that’s it! **Our really simple classifier gave correct answer for 94.4% of validation data!** And everything in exactly 30 lines of code.

I’m really impressed how powerful F# seems to be. Just couple lines of code, everything evaluates just by typing `;;` without hitting F5 and fake console application. I’m totally into that and I’m really going to learn how to use that power in more real-life scenarios. That’s why you can expect more F#-related posts on this blog.