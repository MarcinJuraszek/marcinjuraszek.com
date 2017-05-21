---
layout: post
title: Adding Matt operator to Roslyn - Binding
excerpt_separator: <!--more-->
---

Following on my previous post where I showed [how to add a new operator to C# and Roslyn](adding-matt-operator-to-roslyn-part-1.html) today I'm going to describe how to make further progress on implementing matt operator: `m@`. I already extender the Lexer and Parser to understand that new language construct. The next step is to make Binder aware of our new operator, to make sure it can only be used in the right places and with the right types. We also need to teach the compiler that `<int> m@ <int>` returns an `int`.

<!--more-->

### Iterative & exploratory approach

Similarly to what I did when implementing lexing and parsing support, I decided to go with an exploratory approach:

1. Try to use the new operator
2. See where it fails
3. Fix the problem
4. Go back to 1. untill everything is working as expected

Yesterday I used a Unit Test as validation mechanism. Today I'm actually launching Visual Studio with my custom compiler behind it and try to parse a C# file which uses `m@`. The C# input is super simple:

```csharp
using System;

public class Class1
{
	public Class1()
	{
        	var t = 1 m@ 2;
	}
}
```

With that Visual Studio fails with an exception:

![Bind error in VS](../../images/roslyn-bind-error.png)

And after fixing this one, another similar one came, and so on. I won't show all of them, but instead focus on the changes necessary to make them go away.

### `BinaryOperatorKind` and necessary mapping

First of all, it's necessary to define our new operator in *\roslyn\src\compilers\csharp\portable\binder\semantics\operators\operatorkind.cs* enum. `m@` is a binary operator, so it has to be added to `BinaryOperatorKind`. That enum not only defines all the operators, but also contains a definition of what type can be used with that operator. e.g. here is part of `Addition`-related entries:

```csharp
Addition = 0x00001100,
/// (...)

IntAddition = Int | Addition,
UIntAddition = UInt | Addition,
LongAddition = Long | Addition,
ULongAddition = ULong | Addition,
// (...) +25 similar entries
StringAndObjectConcatenation = StringAndObject | Addition,
ObjectAndStringConcatenation = ObjectAndString | Addition,
DelegateCombination = Delegate | Addition,
DynamicAddition = Dynamic | Addition,
```

To make it easier let's define just `Matt` and `IntMatt`.

```csharp
Matt = 0x00002000,
IntMatt = Int | Matt,
```

With that we can define `SyntaxKind.MattExpression` -> `BinaryOperatorKind.Matt` mapping in *\roslyn\src\Compilers\CSharp\Portable\Binder\Binder_Operators.cs*:

```csharp
private static BinaryOperatorKind SyntaxKindToBinaryOperatorKind(SyntaxKind kind)
{
    switch (kind)
    {
        case SyntaxKind.MultiplyAssignmentExpression:
        case SyntaxKind.MultiplyExpression: return BinaryOperatorKind.Multiplication;
        // (...)
        case SyntaxKind.MattExpression: return BinaryOperatorKind.Matt;
        default: throw ExceptionUtilities.UnexpectedValue(kind);
    }
}
```

We also have to modify `IsSimpleBinaryOperator`

```csharp
protected static bool IsSimpleBinaryOperator(SyntaxKind kind)
{
    // We deliberately exclude &&, ||, ??, etc. 
    switch (kind)
    {
        case SyntaxKind.AddExpression:
        // (...)
        case SyntaxKind.RightShiftExpression:
        case SyntaxKind.MattExpression:
            return true;
    }
    return false;
}
```

and `BindExpressionInternal` in *\roslyn\src\Compilers\CSharp\Portable\Binder\Binder_Expressions.cs*

```csharp
case SyntaxKind.RightShiftExpression:
case SyntaxKind.MattExpression:
    return BindSimpleBinaryOperator((BinaryExpressionSyntax)node, diagnostics);
``` 

### Overload Resolution

In this next step we have to define how Binder should decide what type overload should an expression be resolved to. All that is done in *\roslyn\src\Compilers\CSharp\Portable\Binder\Semantics\Operators\BinaryOperatorEasyOut.cs* in a form of big jagged arrays. Here's a snippet from `s_arithmetic`:

```csharp
// Overload resolution for Y * / - % < > <= >= X
private static readonly BinaryOperatorKind[,] s_arithmetic =
{
    //                    ----------------regular-------------------                       ----------------nullable-------------------
    //          obj  str  bool chr  i08  i16  i32  i64  u08  u16  u32  u64  r32  r64  dec  bool chr  i08  i16  i32  i64  u08  u16  u32  u64  r32  r64  dec  
    /*  obj */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*  str */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /* bool */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*  chr */
            { ERR, ERR, ERR, INT, INT, INT, INT, LNG, INT, INT, UIN, ULG, FLT, DBL, DEC, ERR, LIN, LIN, LIN, LIN, LLG, LIN, LIN, LUN, LUL, LFL, LDB, LDC },
    /*  i08 */
            { ERR, ERR, ERR, INT, INT, INT, INT, LNG, INT, INT, LNG, ERR, FLT, DBL, DEC, ERR, LIN, LIN, LIN, LIN, LLG, LIN, LIN, LLG, ERR, LFL, LDB, LDC },
    /*  i16 */
            { ERR, ERR, ERR, INT, INT, INT, INT, LNG, INT, INT, LNG, ERR, FLT, DBL, DEC, ERR, LIN, LIN, LIN, LIN, LLG, LIN, LIN, LLG, ERR, LFL, LDB, LDC },
    /*  i32 */
            { ERR, ERR, ERR, INT, INT, INT, INT, LNG, INT, INT, LNG, ERR, FLT, DBL, DEC, ERR, LIN, LIN, LIN, LIN, LLG, LIN, LIN, LLG, ERR, LFL, LDB, LDC },
    /*  i64 */
            { ERR, ERR, ERR, LNG, LNG, LNG, LNG, LNG, LNG, LNG, LNG, ERR, FLT, DBL, DEC, ERR, LLG, LLG, LLG, LLG, LLG, LLG, LLG, LLG, ERR, LFL, LDB, LDC },
    // (...) and many more of rows similar to the ones above
```

It's a resolution table, which is later used to see if an operator (in this particular case `*`, `/`, `-`, `%`, `<`, `>`, `<=`, `>=`) is allowed to be used with left and right arguments of a given type, and what is the return type of that expression for these input types. For our implementation of `m@` it should always return `ERR` (which means such usage is not allowed), except for `i32`-`i32` case where we should return `INT` (alias for `BinaryOperatorKind.Int`):

```csharp
// Overload resolution for Y m@ X
private static readonly BinaryOperatorKind[,] s_matt =
{
    //                    ----------------regular-------------------                       ----------------nullable-------------------
    //          obj  str  bool chr  i08  i16  i32  i64  u08  u16  u32  u64  r32  r64  dec  bool chr  i08  i16  i32  i64  u08  u16  u32  u64  r32  r64  dec  
    /*  obj */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*  str */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /* bool */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*  chr */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*  i08 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*  i16 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*  i32 */
            { ERR, ERR, ERR, ERR, ERR, ERR, INT, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*  i64 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*  u08 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*  u16 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*  u32 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*  u64 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*  r32 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*  r64 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*  dec */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /*nbool */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /* nchr */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /* ni08 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /* ni16 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /* ni32 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /* ni64 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /* nu08 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /* nu16 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /* nu32 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /* nu64 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /* nr32 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /* nr64 */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
    /* ndec */
            { ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR, ERR },
};
```

Did you notice that single `INT` in the entire table above? If you missed, check again ;) 

It's also required to add `s_matt` to `s_opkind`. It has to be the last entry, because we defined `BinaryOperatorKind.Matt` after all the other operators.

```csharp
private static readonly BinaryOperatorKind[][,] s_opkind =
{
    /* *  */ s_arithmetic,
    /* +  */ s_addition,
    /* -  */ s_arithmetic,
    /* /  */ s_arithmetic,
    /* %  */ s_arithmetic,
    /* >> */ s_shift,
    /* << */ s_shift,
    /* == */ s_equality,
    /* != */ s_equality,
    /* >  */ s_arithmetic,
    /* <  */ s_arithmetic,
    /* >= */ s_arithmetic,
    /* <= */ s_arithmetic,
    /* &  */ s_logical,
    /* |  */ s_logical,
    /* ^  */ s_logical,
    /* m@ */ s_matt,
};
```
With all these changes Visual Studio is a bit happier when loading a C# file where `m@` is being used. It is able to correctly identify the return value of `1 m@ 2` as `int`:

![Matt operator used in Visual Studio](../../images/roslyn-matt-int.png)

However, as soon as we hover over the operator itself, things stop looking that good.

![Error when hovering over Matt operator in Visual Studio](../../images/roslyn-bind-name-error.png)

### Operator Name

We missed to teach the compiler about `m@` in couple places. 

First of all, we need to add `MattOperatorName` in *\roslyn\src\Compilers\Core\Portable\Symbols\WellKnownMemberNames.cs*:

```csharp
/// <summary>
/// The name assigned to the Matt operator.
/// </summary>
public const string MattOperatorName = "op_Matt";
```

Based on a suggestion from a Code Fix it also has to be added to *\roslyn\src\Compilers\Core\Portable\PublicAPI.Unshipped.txt*:

```csharp
// (...)
abstract Microsoft.CodeAnalysis.SemanticModel.GetOperationCore(Microsoft.CodeAnalysis.SyntaxNode node, System.Threading.CancellationToken cancellationToken) -> Microsoft.CodeAnalysis.IOperation
const Microsoft.CodeAnalysis.WellKnownMemberNames.MattOperatorName = "op_Matt" -> string
// (...)
```

After that's defined we can add it to `BinaryOperatorNameFromOperatorKind` and `BinaryOperatorNameFromSyntaxKindIfAny`:

```csharp
internal static string BinaryOperatorNameFromSyntaxKindIfAny(SyntaxKind kind)
{
    switch (kind)
    {
        case SyntaxKind.PlusToken: return WellKnownMemberNames.AdditionOperatorName;
        // (...)
        case SyntaxKind.ExclamationEqualsToken: return WellKnownMemberNames.InequalityOperatorName;
        case SyntaxKind.MattToken: return WellKnownMemberNames.MattOperatorName;
        default:
            return null;
    }
}
```

```csharp
public static string BinaryOperatorNameFromOperatorKind(BinaryOperatorKind kind)
{
    switch (kind & BinaryOperatorKind.OpMask)
    {
        case BinaryOperatorKind.Addition: return WellKnownMemberNames.AdditionOperatorName;
        // (...)
        case BinaryOperatorKind.Xor: return WellKnownMemberNames.ExclusiveOrOperatorName;
        case BinaryOperatorKind.Matt: return WellKnownMemberNames.MattOperatorName;
        default:
            throw ExceptionUtilities.UnexpectedValue(kind & BinaryOperatorKind.OpMask);
    }
}
```

A similar mapping has to be defined in `GetOperatorKind` to make the tooltip show correct value:

```csharp
public static SyntaxKind GetOperatorKind(string operatorMetadataName)
{
    switch (operatorMetadataName)
    {
        case WellKnownMemberNames.AdditionOperatorName: return SyntaxKind.PlusToken;
        // (...)
        case WellKnownMemberNames.UnaryPlusOperatorName: return SyntaxKind.PlusToken;
        case WellKnownMemberNames.MattOperatorName: return SyntaxKind.MattToken;
        default:
            return SyntaxKind.None;
    }
}
```

With these changes, Visual Studio shows the right tooltip!

![Matt operator property displayed in Visual Studio tooltip](../../images/roslyn-matt-tooltip.png)

### Trying to use `m@` with non-`int` arguments

Everything seemed to be working fine, until I decided to try to use `m@` with non-`int` value:

```csharp
var x = 1 m@ 2d;
```

A set of exceptions guided me towards couple more place where we have to make the compiler aware of Matt operator.

![Error when using Matt operator with a double](../../images/roslyn-double-error.png)

`BuiltInOperators.GetSimpleBuiltInOperators`:

```csharp
var logicalOperators = new ImmutableArray<BinaryOperatorSignature>[]
{
    ImmutableArray<BinaryOperatorSignature>.Empty, //multiplication
    // (...)
    ImmutableArray.Create<BinaryOperatorSignature>(GetSignature(BinaryOperatorKind.LogicalBoolOr)), //or
    ImmutableArray<BinaryOperatorSignature>.Empty, //matt
};
```

```csharp
var nonLogicalOperators = new ImmutableArray<BinaryOperatorSignature>[]
{
    // (...)
    GetSignaturesFromBinaryOperatorKinds(new []
    {
        (int)BinaryOperatorKind.IntMatt,
    }),
};
```

`GetDelegateOperations` and `GetEnumOperations` in *\roslyn\src\Compilers\CSharp\Portable\Binder\Semantics\Operators\BinaryOperatorOverloadResolution.cs*:

```csharp
private void GetDelegateOperations(BinaryOperatorKind kind, BoundExpression left, BoundExpression right,
    ArrayBuilder<BinaryOperatorSignature> operators, ref HashSet<DiagnosticInfo> useSiteDiagnostics)
{
    Debug.Assert(left != null);
    Debug.Assert(right != null);
    AssertNotChecked(kind);

    switch (kind)
    {
        case BinaryOperatorKind.Multiplication:
        // (...)
        case BinaryOperatorKind.LogicalOr:
        case BinaryOperatorKind.Matt:
            return;

        case BinaryOperatorKind.Addition:
        case BinaryOperatorKind.Subtraction:
        case BinaryOperatorKind.Equal:
        case BinaryOperatorKind.NotEqual:
            break;
```

*I'm not realy sure what the difference is. Seems like there are some special cases for `+`, `-` and equality which I don't want to worry about for now.*

```csharp
private void GetEnumOperations(BinaryOperatorKind kind, BoundExpression left, BoundExpression right, ArrayBuilder<BinaryOperatorSignature> results)
{
    Debug.Assert(left != null);
    Debug.Assert(right != null);
    AssertNotChecked(kind);

    // First take some easy outs:
    switch (kind)
    {
        case BinaryOperatorKind.Multiplication:
        case BinaryOperatorKind.Division:
        case BinaryOperatorKind.Remainder:
        case BinaryOperatorKind.RightShift:
        case BinaryOperatorKind.LeftShift:
        case BinaryOperatorKind.LogicalAnd:
        case BinaryOperatorKind.LogicalOr:
        case BinaryOperatorKind.Matt:
            return;
    }
```

### It works!

Looks like these are all the changes needed to make Visual Studio somehow happy. It's able to correctly parse the code, figure out that `m@` can only be used with `int`s, (the return type can't be resolved out if used with non-`int` input) + the right help tooltip is shown when hovered over the new operator. Not bad!

![Compiler failing to resolve Matt operator on double](../../images/roslyn-double-tooltip.png)

Things go south when you try to actually compile the code as part of a project. csc.exe exits with an error code, which is handled by Visual Studio and an exception is thrown.

![csc.exe failing to compile code with Matt operator](../../images/roslyn-compile-error-255.png)

That's totally expected though. We haven't yet touched the last part of Roslyn pipeline - the Emmiter. That's where IL is generated. But that's a topic for next post!

*PS. All the code changes described in this post can be viewed on GitHub: [MarcinJuraszek/roslyn/commit/6d9b2aad5ec78d314749b088697c5a28fe9f6b15](https://github.com/MarcinJuraszek/roslyn/commit/6d9b2aad5ec78d314749b088697c5a28fe9f6b15?diff=unified).*

*PS.2. When looking through the code I noticed that if we wanted to make `Matt` overridable we'd also have to modify `PEMethodSymbol.ComputeMethodKind`. For us, the default value works just fine, so I decided not to touch it. But just saying, in case somebody wants to push it further and allow for custom operators to be defined.*