---
layout: post
title: Adding Matt operator to Roslyn - Syntax, Lexer and Parser
excerpt_separator: <!--more-->
---

I read a very interesting blog post by Matt Warren yesterday morning: *[Adding a new Bytecode Instruction to the CLR](http://mattwarren.org/2017/05/19/Adding-a-new-Bytecode-Instruction-to-the-CLR/)*. It was very eye-opening to see how easy it is to add a new instruction to .NET CLR. In his blogpost Matt started a challange about adding support for his new `matt` operator into C# (Roslyn):

> The other reason for naming it matt is that I’d really like someone to make a version of the C# (Roslyn) compiler that allows you to write code like this:
>
> ```csharp
> Console.WriteLine("{0} m@ {1} = {2}", 1, 7, 1 m@ 7)); // prints '1 m@ 7 = 7'
> ```
>
>I definitely want the `m@` operator to be a thing (pronounced *‘matt’*, not *‘m-at’*), maybe the other ‘Matt Warren’ who works at Microsoft on the C# Language Design Team can help out!! Seriously though, if anyone reading this would like to write a similar blog post, showing how you’d add the `m@` operator to the Roslyn compiler, please let me know I’d love to read it.

Because I always wanted to learn more about Roslyn I decided to explore it a little bit and see how far I can get. I invite you to join me on that journey.

<!--more-->

First of all, I forked and cloned [Roslyn repo](https://github.com/dotnet/roslyn). I also got a beefy VM on Azure running Visual Studio 2017 to make my development faster (having 16 cores and 56 GB Memory makes build so much faster than it would have been on my laptop!). But that's not that interesting. So let's move to code. 

At the beginning I had not the slightest idea on where to start. Roslyn project is quite big. Because of that, instead of trying to just go write the new operator all over the place and hope that it works, I started by exploring what the main pieces of Roslyn pipeline are. I found following documentation page quite informative: [.NET Compiler Platform (“Roslyn”) Overview](https://github.com/dotnet/roslyn/wiki/Roslyn%20Overview). Here is a high-level compiler pipeline diagram:

![Roslyn Compiler pipeline](../../images/matt-operator-roslyn/pipeline.png)

That kind of gave me the idea of what I should start looking for.

The very first piece that's needed is to teach the Parser how to recognize `m@` as a new binary operator. Making that happen is what this post is all about.

### Extending `TestBinaryOperators` to test for `m@`

Instead of trying to find a good place to start writing `m@` support, I decided to start with trying to write a test which would cover parsing that new operator. That's actually the easiest part. Roslyn already has a test which validates parsing of all the binary operators from C# language. We can just add our new operator there:

```csharp
[Fact]
public void TestBinaryOperators()
{
    TestBinary(SyntaxKind.PlusToken);
    // (...)
    TestBinary(SyntaxKind.QuestionQuestionToken);
    TestBinary(SyntaxKind.MattToken);
}
```

Now, that obviously doesn't compile, because we didn't define `SyntaxKind.MattToken` yet. But at least that gives us an idea for the next step!

### Defining `SyntaxKind.MattToken`

As you might guess, I had no idea how to properly define `SyntaxKind.MattToken`. What seems natural is trying to find how some of the other operators are defined and just following that pattern. I decided to go with `SyntaxKind.QuestionQuestionToken` (representing `??`), because it can't be overriden in C#. That means it should be easier to follow than e.g. `++` which has to be handled by compiler in a way that allows developers to override its behavior.

A quick search returns where it's defined: *roslyn\src\Compilers\CSharp\Portable\Syntax\SyntaxKind.cs*. I just added my new token to the same group in that file, using the next available value:

```csharp
// compound punctuation
BarBarToken = 8260,
// (...)
QuestionQuestionToken = 8265,
// (...)
PercentEqualsToken = 8283,
MattToken = 8284,
```

Right when I did that, Visual Studio showed red squiggles, which means I was missing something. The good thing is, Roslyn comes with some Analyzers and Code Fixes, which turned out to be very helpful in that situation:

![Add Token CodeFix](../../images/matt-operator-roslyn/add-token.png)

With the help of that Code Fix `MattToken` was added to *\roslyn\src\Compilers\CSharp\Portable\PublicAPI.Unshipped.txt*

```csharp
   (...)
Microsoft.CodeAnalysis.CSharp.SyntaxKind.DefaultLiteralExpression = 8755 -> Microsoft.CodeAnalysis.CSharp.SyntaxKind
Microsoft.CodeAnalysis.CSharp.SyntaxKind.MattToken = 8284 -> Microsoft.CodeAnalysis.CSharp.SyntaxKind
static Microsoft.CodeAnalysis.CSharp.LanguageVersionFacts.MapSpecifiedToEffectiveVersion(this Microsoft.CodeAnalysis.CSharp.LanguageVersion version) -> Microsoft.CodeAnalysis.CSharp.LanguageVersion
   (...)
```

With that, the code compiles and we can try to run our test (expecting it to fail).

### Running the Unit Test for the first time!

I used [xunit.running.wpf](https://github.com/pilchie/xunit.runner.wpf) to run just that test. It failed, just as expected:

```csharp
Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.TestBinaryOperators FAILED:
	Exception type: 'Xunit.Sdk.EqualException', number: '0', parent: '-1'
	Exception message:
Assert.Equal() Failure
Expected: None
Actual:   CastExpression
	Exception stacktrace
   at Xunit.Assert.Equal[T](T expected, T actual, IEqualityComparer`1 comparer) in C:\BuildAgent\work\cb37e9acf085d108\src\xunit.assert\Asserts\EqualityAsserts.cs:line 40
   at Xunit.Assert.Equal[T](T expected, T actual) in C:\BuildAgent\work\cb37e9acf085d108\src\xunit.assert\Asserts\EqualityAsserts.cs:line 24
   at Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.TestBinary(SyntaxKind kind) in D:\roslyn\src\Compilers\CSharp\Test\Syntax\Parsing\ExpressionParsingTests.cs:line 241
   at Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.TestBinaryOperators() in D:\roslyn\src\Compilers\CSharp\Test\Syntax\Parsing\ExpressionParsingTests.cs:line 277
```

The failure points at the first `Assert` code from the Unit Test:

```csharp
private void TestBinary(SyntaxKind kind)
{
    var text = "(a) " + SyntaxFacts.GetText(kind) + " b";
    var expr = this.ParseExpression(text);

    Assert.NotNull(expr);
    var opKind = SyntaxFacts.GetBinaryExpression(kind);
    Assert.Equal(opKind, expr.Kind());
    // (...)
```

It says `expr.Kind()` is equals to `CastExpression`, but it's expected to be `None`. That's wrong. We want it to be `MattExpression`! But be haven't defined it yet, so let's do that.

### Defining `SyntaxKind.MattExpression`

Again, the easiest way to go is just follow an example of an existing operator. `??` is representing *null-coalescing* operator, so we can use `SyntaxKind.CoalesceExpression` as an template. At the end, similarly to `SyntaxKind.MattToken`, changes need to happen in two places:

*roslyn\src\Compilers\CSharp\Portable\Syntax\SyntaxKind.cs*

```csharp
// binary expressions
AddExpression = 8668,
// (...)
CoalesceExpression = 8688,
// (...)
MattExpression = 8692,
```

*\roslyn\src\Compilers\CSharp\Portable\PublicAPI.Unshipped.txt*

```csharp
    (...)
Microsoft.CodeAnalysis.CSharp.SyntaxKind.DefaultLiteralExpression = 8755 -> Microsoft.CodeAnalysis.CSharp.SyntaxKind
Microsoft.CodeAnalysis.CSharp.SyntaxKind.MattExpression = 8692 -> Microsoft.CodeAnalysis.CSharp.SyntaxKind
Microsoft.CodeAnalysis.CSharp.SyntaxKind.MattToken = 8284 -> Microsoft.CodeAnalysis.CSharp.SyntaxKind
    (...)
```

### `SyntaxFacts` for `m@` operator

Back to the test. You've probably noticed that before the assertion fails, `TestBinary` calls into two methods on `SyntaxFacts`: `GetText` and `GetBinaryExpression` as well as a single call into `ParseExpression` - to do the actual parsing. Let's look into `SyntaxFacts` first.

`SyntaxKind.GetText` returns string representation of a given `SyntaxKind`. We already know what needs to be returned for `SyntaxKind.MattToken`, so let's make that happen:

```csharp
// compound
(case SyntaxKind.BarBarToken:
    return "||";
// (...)
case SyntaxKind.QuestionQuestionToken:
    return "??";
// (...)
case SyntaxKind.MattToken:
    return "m@";

// (...)
```

`SyntaxKind.GetBinaryExpression` matches a token with an expression. We need to add `SyntaxKind.MattToken` -> `SyntaxKind.MattExpression` mapping there:

```csharp
public static SyntaxKind GetBinaryExpression(SyntaxKind token)
{
    switch (token)
    {
        case SyntaxKind.QuestionQuestionToken:
            return SyntaxKind.CoalesceExpression;
            (...)
        case SyntaxKind.MattToken:
            return SyntaxKind.MattExpression;
        default:
            return SyntaxKind.None;
    }
}
```

Reruning the test with these changes proves we're now expecting the right parsing result:

```csharp
Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.TestBinaryOperators FAILED:
	Exception type: 'Xunit.Sdk.EqualException', number: '0', parent: '-1'
	Exception message:
Assert.Equal() Failure
Expected: MattExpression
Actual:   CastExpression
	Exception stacktrace
   at Xunit.Assert.Equal[T](T expected, T actual, IEqualityComparer`1 comparer) in C:\BuildAgent\work\cb37e9acf085d108\src\xunit.assert\Asserts\EqualityAsserts.cs:line 40
   at Xunit.Assert.Equal[T](T expected, T actual) in C:\BuildAgent\work\cb37e9acf085d108\src\xunit.assert\Asserts\EqualityAsserts.cs:line 24
   at Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.TestBinary(SyntaxKind kind) in D:\roslyn\src\Compilers\CSharp\Test\Syntax\Parsing\ExpressionParsingTests.cs:line 241
   at Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.TestBinaryOperators() in D:\roslyn\src\Compilers\CSharp\Test\Syntax\Parsing\ExpressionParsingTests.cs:line 277
```

With that, we can move to the next step - lexing & parsing logic!

### Lexing `m@`

Following a bunch of method calls from `var expr = this.ParseExpression(text);` in the test I ended up all the way in the Lexer: `Lexer.ScanSyntaxToken` method to be exact. That's where actual [lexing](https://en.wikipedia.org/wiki/Lexical_analysis) happens - which means that's the place where our `m@` -> `SyntaxKind.MattToken` needs to happen. 

`ScanSyntaxToken` is basically a huge `switch` statement reading charactes from the provided text input (source code) and trying to match them into tokens based on meaning assigned to them by language designers. The easiest example would be how parsing a semicolon is achieved:

```csharp
case ';':
    TextWindow.AdvanceChar();
    info.Kind = SyntaxKind.SemicolonToken;
    break;
```

We need to extend that switch statement to properly recognize `m@`. It's not really that complicated after all.

```csharp
case 'm':
    if (TextWindow.PeekChar(1) == '@')
    {
        TextWindow.AdvanceChar(2);
        info.Kind = SyntaxKind.MattToken;
        break;
    }

    goto case 'a';

// All the 'common' identifier characters are represented directly in
// these switch cases for optimal perf.  Calling IsIdentifierChar() functions is relatively
// expensive.
case 'a':
// (...)
// case 'm': - remove this one
case 'n':
// (...)
case '_':
    this.ScanIdentifierOrKeyword(ref info);
    break;
```

As you can see, we only have access to a single characted. That means we have to look for `m` first. When `m` is matched we can peek the next character using `PeekChar(1)` and compare it to `@`. If it also matches we found our `MattToken`! We can eat both `m` and `@` and return the right token type. If not, we want to fallback to old bahavior, which will try read out an identifier or keyword.

Let's see if that makes our test move further:

```csharp
Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.TestBinaryOperators FAILED:
	Exception type: 'Microsoft.CodeAnalysis.ThrowingTraceListener+DebugAssertFailureException', number: '0', parent: '-1'
	Exception message:


	Exception stacktrace
   at Microsoft.CodeAnalysis.ThrowingTraceListener.Fail(String message, String detailMessage)
   at System.Diagnostics.TraceListener.Fail(String message)
   at System.Diagnostics.TraceInternal.Fail(String message)
   at System.Diagnostics.Debug.Assert(Boolean condition)
   at Microsoft.CodeAnalysis.CSharp.Syntax.InternalSyntax.LanguageParser.ParseSubExpressionCore(Precedence precedence)
   at Microsoft.CodeAnalysis.CSharp.Syntax.InternalSyntax.LanguageParser.ParseSubExpression(Precedence precedence)
   at Microsoft.CodeAnalysis.CSharp.Syntax.InternalSyntax.LanguageParser.ParseCastOrParenExpressionOrLambdaOrTuple(Precedence precedence)
   at Microsoft.CodeAnalysis.CSharp.Syntax.InternalSyntax.LanguageParser.ParseTerm(Precedence precedence)
   at Microsoft.CodeAnalysis.CSharp.Syntax.InternalSyntax.LanguageParser.ParseSubExpressionCore(Precedence precedence)
   at Microsoft.CodeAnalysis.CSharp.Syntax.InternalSyntax.LanguageParser.ParseSubExpression(Precedence precedence)
   at Microsoft.CodeAnalysis.CSharp.Syntax.InternalSyntax.LanguageParser.ParseExpressionCore()
   at Microsoft.CodeAnalysis.CSharp.Syntax.InternalSyntax.LanguageParser.ParseWithStackGuard[TNode](Func`1 parseFunc, Func`1 createEmptyNodeFunc)
   at Microsoft.CodeAnalysis.CSharp.Syntax.InternalSyntax.LanguageParser.ParseExpression()
   at Microsoft.CodeAnalysis.CSharp.SyntaxFactory.ParseExpression(String text, Int32 offset, ParseOptions options, Boolean consumeFullText)
   at Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.ParseExpression(String text, ParseOptions options) in D:\roslyn\src\Compilers\CSharp\Test\Syntax\Parsing\ExpressionParsingTests.cs:line 23
   at Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.TestBinary(SyntaxKind kind) in D:\roslyn\src\Compilers\CSharp\Test\Syntax\Parsing\ExpressionParsingTests.cs:line 237
   at Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.TestBinaryOperators() in D:\roslyn\src\Compilers\CSharp\Test\Syntax\Parsing\ExpressionParsingTests.cs:line 277
```

Sweet. A new failure exception! I'm happy about that, because that means we were able to solve previous failure and uncover a new problem with our code. Let's fix it!

### Setting a precedence for `m@`

That failure points at a `Debug.Assert` in `LanguageParser.ParseSubExpressionCore`. Fortunately it's quite clear what the problem is:

```csharp
newPrecedence = GetPrecedence(opKind);

Debug.Assert(newPrecedence > 0);      // All binary operators must have precedence > 0!
```

We didn't set a precedence for our new operator! Let's fix that real quick. I decided to set it at the same level `+` and `-` are set - before bit shifting but after multiplication and division.

```csharp
case SyntaxKind.LeftShiftExpression:
case SyntaxKind.RightShiftExpression:
    return Precedence.Shift;
case SyntaxKind.AddExpression:
case SyntaxKind.SubtractExpression:
case SyntaxKind.MattExpression:
    return Precedence.Additive;
case SyntaxKind.MultiplyExpression:
case SyntaxKind.DivideExpression:
case SyntaxKind.ModuloExpression:
    return Precedence.Mutiplicative;
```

Rerunning the test makes the last failure go away, and a new one shows up.

```csharp
Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.TestBinaryOperators FAILED:
	Exception type: 'System.ArgumentException', number: '0', parent: '-1'
	Exception message:
kind
	Exception stacktrace
   at Microsoft.CodeAnalysis.CSharp.Syntax.InternalSyntax.ContextAwareSyntax.BinaryExpression(SyntaxKind kind, ExpressionSyntax left, SyntaxToken operatorToken, ExpressionSyntax right)
   at Microsoft.CodeAnalysis.CSharp.Syntax.InternalSyntax.LanguageParser.ParseSubExpressionCore(Precedence precedence)
   at Microsoft.CodeAnalysis.CSharp.Syntax.InternalSyntax.LanguageParser.ParseSubExpression(Precedence precedence)
   at Microsoft.CodeAnalysis.CSharp.Syntax.InternalSyntax.LanguageParser.ParseExpressionCore()
   at Microsoft.CodeAnalysis.CSharp.Syntax.InternalSyntax.LanguageParser.ParseWithStackGuard[TNode](Func`1 parseFunc, Func`1 createEmptyNodeFunc)
   at Microsoft.CodeAnalysis.CSharp.Syntax.InternalSyntax.LanguageParser.ParseExpression()
   at Microsoft.CodeAnalysis.CSharp.SyntaxFactory.ParseExpression(String text, Int32 offset, ParseOptions options, Boolean consumeFullText)
   at Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.ParseExpression(String text, ParseOptions options) in D:\roslyn\src\Compilers\CSharp\Test\Syntax\Parsing\ExpressionParsingTests.cs:line 23
   at Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.TestBinary(SyntaxKind kind) in D:\roslyn\src\Compilers\CSharp\Test\Syntax\Parsing\ExpressionParsingTests.cs:line 237
   at Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.TestBinaryOperators() in D:\roslyn\src\Compilers\CSharp\Test\Syntax\Parsing\ExpressionParsingTests.cs:line 277
```

This time there is an exception thrown in `ContextAwareSyntax.BinaryExpression`. Let's dig into that next.

### Generating compiler code

Turns out that class is part of *\roslyn\src\Compilers\CSharp\Portable\Generated\Syntax.xml.Internal.Generated.cs* and it's auto-generated. Now, I'd expect it to be regenerated during build, but it's not, so it still doesn't have our `MattToken` and `MattExpression`. To fix that, we have to add our new `SyntaxKind` entries to *roslyn\src\Compilers\CSharp\Portable\Syntax\Syntax.xml* and manually regenerate it by running `buils\scripts\generate-compiler-code.cmd`:

```xml
  <Node Name="BinaryExpressionSyntax" Base="ExpressionSyntax">
    <Kind Name="AddExpression"/>
    <!-- (...) -->
    <Kind Name="CoalesceExpression"/>
    <Kind Name="MattExpression"/>
    <Field Name="Left" Type="ExpressionSyntax">
      <PropertyComment>
        <summary>ExpressionSyntax node representing the expression on the left of the binary operator.</summary>
      </PropertyComment>
    </Field>
    <Field Name="OperatorToken" Type="SyntaxToken">
      <Kind Name="PlusToken"/>
      <!-- (...) -->
      <Kind Name="QuestionQuestionToken"/>
      <Kind Name="MattToken"/>
      <PropertyComment>
        <summary>SyntaxToken representing the operator of the binary expression.</summary>
      </PropertyComment>
    </Field>
    <!-- (...) -->
  </Node>
```

```bash
D:\roslyn>build\scripts\generate-compiler-code.cmd
Using existing NuGet.exe at version 4.1.0
Building CompilersBoundTreeGenerator
Building CSharpErrorFactsGenerator
Building CSharpSyntaxGenerator
Building VisualBasicErrorFactsGenerator
Building VisualBasicSyntaxGenerator
Running CSharpSyntaxGenerator.exe
Running CSharpSyntaxGenerator.exe
Running BoundTreeGenerator.exe
Running CSharpErrorFactsGenerator.exe
Running VBSyntaxGenerator.exe
Running VBSyntaxGenerator.exe
Running BoundTreeGenerator.exe
Running VBErrorFactsGenerator.exe
Running VBSyntaxGenerator.exe
```

Another test run proves that we moved pass that failure and can move on to the next one.

```
Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.TestBinaryOperators FAILED:
	Exception type: 'Xunit.Sdk.EqualException', number: '0', parent: '-1'
	Exception message:
Assert.Equal() Failure
Expected: 0
Actual:   1
	Exception stacktrace
   at Xunit.Assert.Equal[T](T expected, T actual, IEqualityComparer`1 comparer) in C:\BuildAgent\work\cb37e9acf085d108\src\xunit.assert\Asserts\EqualityAsserts.cs:line 40
   at Xunit.Assert.Equal[T](T expected, T actual) in C:\BuildAgent\work\cb37e9acf085d108\src\xunit.assert\Asserts\EqualityAsserts.cs:line 24
   at Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.TestBinary(SyntaxKind kind) in D:\roslyn\src\Compilers\CSharp\Test\Syntax\Parsing\ExpressionParsingTests.cs:line 243
   at Microsoft.CodeAnalysis.CSharp.UnitTests.ExpressionParsingTexts.TestBinaryOperators() in D:\roslyn\src\Compilers\CSharp\Test\Syntax\Parsing\ExpressionParsingTests.cs:line 256
```

Nice! We finally got pass the first couple `Assert`s!. Here is currently failing validation:

```csharp
Assert.Equal(0, expr.Errors().Length);
```

### `CastExpression` vs. `ParenthesizedExpression`

Even though I wasn't able to get UT debugging working, here is some of the error returned by Lexer:

```
error CS1525: Invalid expression term 'm@···
```

The problem is with how `(a)` from the input string is recognized. For all the binary operators it's parsed as `ParenthesizedExpression`, but for our new `MattToken` it's recognized as `CastExpression`. And `@m b` can't be cast to type `a` and that's what's causing the error. That's easy to fix: we just have to add `MattToken` to `LanguageParser.CanFollowCast`:

```csharp
private static bool CanFollowCast(SyntaxKind kind)
{
    switch (kind)
    {
        case SyntaxKind.AsKeyword:
        // (...)
        case SyntaxKind.EndOfFileToken:
        case SyntaxKind.MattToken:
            return false;
        default:
            return true;
    }
}
```

## Success!

With that last fix all the Unit Tests are passing, which means Roslyn now knows how to parse `m@` and how that new Token interacts with the rest of Syntax Tree!

I tried proving that by launching the project. It will start a new instace of Visual Studio which will use Roslyn compiler built from our local code. I planned to use  [Syntax Visualizer] to  inspect the syntax tree and expected to see `MattExpression` and `MattToken` there, but unfortunately VS throws exceptions because Binder doesn't know how to deal with that new command:

![Bind error in VS](../../images/matt-operator-roslyn/bind-error.png)

Well, we'll try to fix that later.

#### Next steps

To summarize - I think you'll agree that all the changes are quite simple. However, overall it took me few hours to get it all working. That's mainly because I had no previous experience with Roslyn codebase. I'm sure somebody with good understanding of the project could implement all of that in several minutes.

I learned a lot already, but that's definitely not the end of my exploration in Roslyn codebase. The next goal -> implement the right binding and emit the correct IL code to actually call `matt` command in CLR!


*PS. All of the above changes can be reviewed on GitHub in [marcinjuraszek/Roslyn](https://github.com/MarcinJuraszek/roslyn/tree/mattOperator) - see [lexing and parsing](https://github.com/MarcinJuraszek/roslyn/commit/adab7844f04f858405ee259a083f7880f9a071cc)* commit for a diff.

PS.2. **The second part of the series is now out: [Adding Matt operator to Roslyn - Binding](adding-matt-operator-to-roslyn-part-2.html)**.

PS.3. **The third part of the series is now out: [Adding Matt operator to Roslyn - Emitter](adding-matt-operator-to-roslyn-part-3.html)**.