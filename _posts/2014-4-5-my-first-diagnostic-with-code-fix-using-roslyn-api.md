---
layout: post
title: My first “Diagnostic with Code Fix” using Roslyn API
excerpt_separator: <!--more-->
---

I think everyone already knows that during //Build conference Anders Hejlsberg announced that **Roslyn API (renamed to [.NET Compiler Platform](http://roslyn.codeplex.com/)) is now an open source project** (he actually clicked *Publish* button live, on stage). It’s really a great news. But even though a lot of people think that main purpose of that move is to allow everyone to make his own version of C#, I don’t think that’s true. I think the main purpose of Roslyn project is still the same – to provide modern and open compiler infrastructure which will make extension development much easier, because **extension code now knows exactly the same stuff compiler does**. Because of that I decided to give it a try and write simple Diagnostic with Code Fix.

<!--more-->

Roslyn code published on codeplex contains not only the Roslyn API. It also contains couple new, **not yet official and published C# language feature**. One of them is called Declaration Expressions, and allows you e.g. to declare variable as part of method call, which is **quite useful when dealing with out arguments**. Consider common way of using `int.TryParse` method:

```
int value;
if(int.TryParse(input, out value))
{
    // (...)
}
```

right now, with Declaration Expression feature you can declare value within `TryParse` method call itself:

```
if(int.TryParse(input, out int value))
{
    // (...)
}
```

That’s pretty cool. And actually **that’s exactly what my Diagnostic with Code Fix will do**: find all method calls with out modifier, check if it’s possible to move standard variable declaration to the method call itself and propose to apply the change. That’s the final result I’m going to work on:

Having Roslyn Preview already installed, you can go to *File -> New -> Project* and you’ll see **new project group called Roslyn, with tree project types**. The one I’m interested in is called *Diagnostic with Code Fix*.

When you create a project using that template you’ll get two files: `CodeFixProvider.cs` and `DiagnosticAnalyzer.cs`. The first one contains a fix you’d like to apply to certain parts of code files (shown as **light bulb icons left to the source code**). The second one contains an analyzer which is being called by IDE to check if there is any actions you’d like to provide for given code fragments (shown as **green underlines within the source**). I’m going to start with that one.

## DiagnosticAnalyzer

By default, `DiagnosticAnalyzer` class implements `ISymbolAnalyzer`. Unfortunately, that’s not the one we need for our project. **We want to analyze Syntax nodes, not symbols.** To do that, we have to use `ISyntaxNodeAnalyzer<SyntaxKind>`. Let’s change the interface and adopt string literals to match out new Diagnostic.

```
[DiagnosticAnalyzer]
[ExportDiagnosticAnalyzer(DiagnosticId, LanguageNames.CSharp)]
public class DiagnosticAnalyzer : ISyntaxNodeAnalyzer
{
    internal const string DiagnosticId = "UseDeclarationExpressionDiagnostic";
    internal const string Description = "Variable can be declared as part of method call, using Declaration Expression syntax.";
    internal const string MessageFormat = "'{0}' can be declared as part of method call, using Declaration Expression syntax.";
    internal const string Category = "Refactoring";

    internal static DiagnosticDescriptor Rule = new DiagnosticDescriptor(DiagnosticId, Description, MessageFormat, Category, DiagnosticSeverity.Warning);

    public ImmutableArray SupportedDiagnostics { get { return ImmutableArray.Create(Rule); } }

    public ImmutableArray SyntaxKindsOfInterest { get { throw new NotImplementedException(); } }

    public void AnalyzeNode(SyntaxNode node, SemanticModel semanticModel, Action addDiagnostic, CancellationToken cancellationToken)
    {
        throw new NotImplementedException();
    }
}
```

First of all, we have to declare what kind of syntax nodes we are interested in. **You can use [Roslyn Syntax Visualizer](http://roslyn.codeplex.com/wikipage?title=Syntax%20Visualizer&referringTitle=Home) to see what kind of nodes you can choose from.** For our project, we’re only interested in method arguments, which is represented by `SyntaxKind.Argument`:

```
public ImmutableArray SyntaxKindsOfInterest
{
    get
    {
        return ImmutableArray.Create(SyntaxKind.Argument);
    }
}
```

Now, lets implement `AnalyzeNode` method, which is being called by IDE every time one of syntax nodes set we set using `SyntaxKindsOfInterest` appears in users source code. Starting from beginning, we need to **make sure we’re dealing with method call argument, which uses out modifier and does not use Declaration Expression** feature.

```
// check if we're dealing with method argument with out keyqord
// which does not use DeclarationExpression
var argument = node as ArgumentSyntax;
if (argument == null || !argument.RefOrOutKeyword.IsKind(SyntaxKind.OutKeyword) ||
    !argument.Expression.IsKind(SyntaxKind.IdentifierName))
    return;
```

Because we’re going to have quite few conditional expressions like this one, which can potentially prevent further method execution, I decided to go with early return statement convention over nested if statements.

Now, as we know the variable used as out method parameter, **let’s find place where it’s declared**. Because we’re going to need that functionality again within code fix, lets close it within static helper method.

```
public static VariableDeclaratorSyntax GetDeclaration(ArgumentSyntax argument, SemanticModel semanticModel, CancellationToken cancellationToken, out SymbolInfo? info)
{
    info = null;

    var identifier = argument.Expression as IdentifierNameSyntax;
    if (identifier == null)
        return null;

    info = semanticModel.GetSymbolInfo(identifier);
    var symbol = info.Value.Symbol;
    if (symbol == null || symbol.Kind != SymbolKind.Local || symbol.IsImplicitlyDeclared)
        return null;

    var declarators = symbol.DeclaringSyntaxReferences;
    if (declarators == null || declarators.Length != 1)
        return null;

    var declarator = declarators[0];
    return declarator.GetSyntax(cancellationToken) as VariableDeclaratorSyntax;
}
```

It uses `SemanticModel` to find, if the identifier is a local variable (that’s the only one type of variables we’re interested in). It returns `VariableDeclaratorSyntax`. To make a little more clear what it really means, let’s look how a local variable declaration is represented within Syntax Tree.

`VariableDeclaratorSyntax` represents one variable declaration, which is exactly what we’re looking for. Now, we can use that method to get declaration syntax for the argument we’re analyzing:

```
var declarator = GetDeclaration(argument, semanticModel, cancellationToken, out SymbolInfo? info);
if (!info.HasValue || declarator == null)
    return;
```

We also need to make sure, that variable used as method call argument is not used in place, which would be out of scope after introducing Declaration Expression. To do so, we need to **find all places variable is being used**, and check if they fall within new scope span. I decided to simply travers the syntax tree instead of using more high-level APIs, like Workspace API. **For local variable, we can narrow search scope to nearest statement containing variable declaration.**

```
// get containing statement for our variable declaration
var declaratorStatement = declarator.Parent.Parent;
var statement = GetContainingStatement(declaratorStatement);
if (statement == null)
    return;

// get all variable usages within that statement,
// traversing syntax tree, looking for IdentifierNameSyntax nodes
// and checking if that's the same variable we're working on
var usages = statement.DescendantNodes()
    .OfType()
    .Where(x => semanticModel.GetSymbolInfo(x).Equals(info.Value))
    .ToList();

// get containing statement for method call argument
// and new scope span
var argumentStatement = GetContainingStatement(argument);
var span = new TextSpan(argumentStatement.Span.Start,
    argumentStatement.Span.End - argumentStatement.Span.Start);

// check if all usages fall within scope and declare our diagnostic if so
if (usages.All(x => span.Contains(x.Span)))
{
    addDiagnostic(Diagnostic.Create(Rule, argument.GetLocation(), info.Value.Symbol.Name));
}
```

GetContainingStatement is declared as:

```
public static SyntaxNode GetContainingStatement(SyntaxNode node)
{
    var parent = node.Parent;
    while (parent != null && !(parent is StatementSyntax))
        parent = parent.Parent;
    return parent as StatementSyntax;
}
```

That will make wavy, green underline appear under every method call argument with `out` modifier, which could contain Declaration Expression, but does not. Now, let’s prepare a code fix, to fix that issue and introduce Declaration Expression in such cases.

## CodeFixProvider

There are two parts of CodeFixProvider you have to write. First one is `GetFixesAsync` async method, where we should get all necessary info about position diagnostic is being invoke in, and create `CodeAction` which will **perform a fix when invoked by user**.

```
public async Task<IEnumerable<CodeAction>> GetFixesAsync(Document document, TextSpan span, IEnumerable<Diagnostic> diagnostics, CancellationToken cancellationToken)
{
    var root = await document.GetSyntaxRootAsync(cancellationToken);
    var diagnosticSpan = diagnostics.First().Location.SourceSpan;

    var argument = root.FindToken(diagnosticSpan.Start).Parent as ArgumentSyntax;
    if (argument == null)
        return null;

    var semanticModel = await document.GetSemanticModelAsync(cancellationToken);
    var declarator = DiagnosticAnalyzer.GetDeclaration(argument, semanticModel, cancellationToken, out SymbolInfo? info);
    if (declarator == null || !info.HasValue)
        return Enumerable.Empty<CodeAction>();

    return new[] { CodeAction.Create("Use declaration expression", c => UseDeclarationExpression(document, argument, declarator, c)) };
} 
```

It’s quite easy. Just **get syntax nodes we need** (argument and declaration) and **declare an action delegate**. Action itself is much more interesting.

```
private async Task<Document> UseDeclarationExpression(Document document, ArgumentSyntax argument, VariableDeclaratorSyntax declarator,
    CancellationToken cancellationToken)
{
    // get variable declaration
    var declaration = declarator.Parent;

    // get statement which contains both local declaration statement and method call with out argument
    var statement = DiagnosticAnalyzer.GetContainingStatement(declaration.Parent);

    // remove entire local declaration statement or just single variable declaration
    // depending on how many variables are declared within single local declaration statement
    var nodeToRemove = declaration.ChildNodes().OfType<VariableDeclaratorSyntax>().Count() > 1 ? declarator : declaration.Parent;
    var newStatement = statement.RemoveNode(nodeToRemove, SyntaxRemoveOptions.KeepEndOfLine);

    // get variable type
    var type = declaration.ChildNodes().First() as TypeSyntax;
    // create new Declaration Expression using variable type and declarator
    var newDeclarationExpression = SyntaxFactory.DeclarationExpression(type, declarator);
    // fix the trivia aroung Declaration Expression
    var firstToken = newDeclarationExpression.GetFirstToken();
    var leadingTrivia = firstToken.LeadingTrivia;
    var trimmedDeclarationExpression = newDeclarationExpression.ReplaceToken(firstToken, firstToken.WithLeadingTrivia(SyntaxTriviaList.Empty));
    // get ArgumentSyntax from newStatement which is equivalent to argument from original syntax tree
    var newArgument = newStatement.DescendantNodes()
                                    .FirstOrDefault(n => n.IsEquivalentTo(argument));
    // replace argument with new version, containing Declaration Expression
    newStatement = newStatement.ReplaceNode(newArgument.ChildNodes().First(), trimmedDeclarationExpression);

    // get root for current document and replace statement with new version
    var root = await document.GetSyntaxRootAsync(cancellationToken);
    var newRoot = root.ReplaceNode(statement, newStatement);

    // return document with modified syntax
    return document.WithSyntaxRoot(newRoot);
}
```

Some stuff to point out:

- **Roslyn API heavily uses immutable data structures.** That’s why instead of modifying existing syntax tree, we’re creating new one based on the original.
- Because of that, if you need to perform couple different actions on the same tree, you have to be careful. When you try to replace/remove node within new tree, passing one taken from original syntax tree as original nothing will be changed. **You have to search for equivalent node in new tree.**

And actually that’s it. We have working Diagnostic with Code Fix. I have to admit, **I have no idea if that’s the best way to write that kind of extensions**. But it works, looks clear and straight forward. If you think something should be written differently or there is a bug in that code, feel free to point that out in a comment. **I’m really looking forward to learning more about Roslyn and .NET compiler platform.**

Final source code can be found on codeplex: https://marcinjuraszek.codeplex.com/SourceControl/latest#UseDeclarationExpressionDiagnostic/