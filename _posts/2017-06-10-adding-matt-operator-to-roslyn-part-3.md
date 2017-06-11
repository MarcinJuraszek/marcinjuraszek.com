---
layout: post
title: Adding Matt operator to Roslyn - Emitter
excerpt_separator: <!--more-->
---

The last missing piece to get a new operator: `m@` (*matt*) into C# and Roslyn - Emitter. That's the piece that translates C# code into [IL](https://en.wikipedia.org/wiki/Common_Intermediate_Language), which is than run by the runtime.

<!--more-->

This post and all changes described here build on top of the changes I previously made to teach [Lexer, Parser](adding-matt-operator-to-roslyn-part-1.html) and [Binder](adding-matt-operator-to-roslyn-part-2.html) about `Matt` operator.

### The End Goal

Our goal is quite simple: we want `m@` to be translated into `matt` when Roslyn generates IL. Here's how it works for binary `+` operator based on a simple static method:

```csharp
public static int Add(int a, int b)
{
        return a + b;
}
```

This simple C# code ends up as not much more complicated IL:

```
// Code size        4 (0x4)
.maxstack  2
IL_0000:  ldarg.0
IL_0001:  ldarg.1
IL_0002:  add
IL_0003:  ret
```

That should give you some idea of what I'm trying to achieve. For a similar method with `m@` operator:

```csharp
public static int Matt(int a, int b)
{
        return a m@ b;
}
```

Roslyn should generate following IL:

```
// Code size        4 (0x4)
.maxstack  2
IL_0000:  ldarg.0
IL_0001:  ldarg.1
IL_0002:  matt
IL_0003:  ret
```

### Our approach

The easiest way to iterate quickly is to have a Unit Test verifying emitter result against our end goal. The test is quite simple. I added it in `CodeGenOperatorTests` class.

```csharp
        [Fact]
        public void Test_MattOperator()
        {
            var text = @"
class MyClass
{
    public static int Main()
    {
        return 0;
    }

    public static int Matt(int a, int b)
    {
        return a m@ b;
    }
}
";

            var comp = CompileAndVerify(text, verify: false);
            comp.VerifyIL("MyClass.Matt", @"
{
  // Code size        4 (0x4)
  .maxstack  2
  IL_0000:  ldarg.0
  IL_0001:  ldarg.1
  IL_0002:  matt
  IL_0003:  ret
}");
        }
```

Without any changes in emitter that newly added test fails misserably, as expected:

```
Microsoft.CodeAnalysis.CSharp.UnitTests.CodeGen.CodeGenOperatorTests.Test_MattOperator FAILED:
	Exception type: 'Microsoft.CodeAnalysis.ThrowingTraceListener+DebugAssertFailureException', number: '0', parent: '-1'
	Exception message:
Unexpected value 'Matt' of type 'Microsoft.CodeAnalysis.CSharp.BinaryOperatorKind'

	Exception stacktrace
   at Microsoft.CodeAnalysis.ThrowingTraceListener.Fail(String message, String detailMessage)
   at System.Diagnostics.TraceListener.Fail(String message)
   at System.Diagnostics.TraceInternal.Fail(String message)
   at System.Diagnostics.Debug.Assert(Boolean condition, String message)
   at Roslyn.Utilities.ExceptionUtilities.UnexpectedValue(Object o)
   at Microsoft.CodeAnalysis.CSharp.CodeGen.CodeGenerator.EmitBinaryOperatorInstruction(BoundBinaryOperator expression)
   at Microsoft.CodeAnalysis.CSharp.CodeGen.CodeGenerator.EmitBinaryOperatorSimple(BoundBinaryOperator expression)
   (...)
```

I used [xunit.runner.wpf](https://github.com/pilchie/xunit.runner.wpf) to run the test.

Running a test like this is a great way to get a starting point for necessary changes - the failure points at the exact place where something is not aware of `Matt` operator: `EmitBinaryOperatorInstruction` method in `CodeGenerator` class. So that's where we should start making our changes.

### Updating `CodeGenerator`

The change seems quite simple: `EmitBinaryOperatorInstruction` is a simple `switch` statemenet ove `BinaryOperatorKind`. We just have to add a new `case` to handle `BinaryOperatorKind.Matt`:

```csharp
private void EmitBinaryOperatorInstruction(BoundBinaryOperator expression)
{
        switch (expression.OperatorKind.Operator())
        {
                // (...)

                case BinaryOperatorKind.Matt:
                        _builder.EmitOpCode(ILOpCode.??);
                break;

                default:
                throw ExceptionUtilities.UnexpectedValue(expression.OperatorKind.Operator());
        }
}
```

There is just one problem: **`ILOpCode` does not contain `Matt` member**. And it's not even part of Roslyn, so it's not like we can go ahead and add it there. It comes from `System.Reflection.Metadata` assembly, which is part of BCL. If `m@` was a real thing being added to the language, it would most likely be added to the BCL, to allow it to be emitted by Roslyn and by user-defined code at runtime.

Let's see if updating this method will actually make our test generate some IL. I used `ILOpCode.Or` for that:

```csharp
                case BinaryOperatorKind.Matt:
                        _builder.EmitOpCode(ILOpCode.Or);
                break;
```

Recompiling the necessary projects and rerunning the test shows that we're at the right track:

```
Microsoft.CodeAnalysis.CSharp.UnitTests.CodeGen.CodeGenOperatorTests.Test_MattOperator FAILED:
	Exception type: 'Xunit.Sdk.TrueException', number: '0', parent: '-1'
	Exception message:

Expected:
{
  // Code size        4 (0x4)
  .maxstack  2
  IL_0000:  ldarg.0
  IL_0001:  ldarg.1
  IL_0002:  matt
  IL_0003:  ret
}
Actual:
{
  // Code size        4 (0x4)
  .maxstack  2
  IL_0000:  ldarg.0
  IL_0001:  ldarg.1
  IL_0002:  or
  IL_0003:  ret
}
Differences:
    {
      // Code size        4 (0x4)
      .maxstack  2
      IL_0000:  ldarg.0
      IL_0001:  ldarg.1
++>   IL_0002:  or
-->   IL_0002:  matt
      IL_0003:  ret
    }
```

Well, that's quite good. **If only we were able to provide the right `ILOpCode` everything would have just worked.**

`System.Reflection.Metadata` is public on GitHub as part of [CoreFX repository](https://github.com/dotnet/corefx/tree/master/src/System.Reflection.Metadata). You could enlist in the repo, and modify  [`ILOpCode`](https://github.com/dotnet/corefx/blob/master/src/System.Reflection.Metadata/src/System/Reflection/Metadata/IL/ILOpCode.cs) to add `Matt` instruction there.

The thing is, it feels a bit outside of my initial goal of getting familiar with Roslyn repository by trying to add a new operator to C#. Because of that, I won't be pursuing that `ILOpCode` change. Feel free to do it yourself, write a post about it and send me a link - I would definitely read it myself, and I'm sure there is more people that would be interested in how to get custom version of BCL and use it in a project like Roslyn.

### Summary

So that's it, the end of the series. It wasn't really that hard to add a new operator to Roslyn. The codebase, even though it's huge and complicated, is well structured, with a good set of Unit Tests which provide a good entry point when trying to add new functionality: adding a test first and trying to make the necessary changes to make it work (following TDD principle).  It's also easy to see your changes live in Visual Studio by simply starting a debugging session from Visual Studio.

It might feel a bit dissapointing that I wasn't able to get end-to-end scenario working, but it still was a fun excercise :) I hope you enjoyed the posts as much as I enjoyed working on them.