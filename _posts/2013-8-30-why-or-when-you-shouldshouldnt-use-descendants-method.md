---
layout: post
title: Why (or when) you should/shouldn’t use Descendants() method
excerpt_separator: <!--more-->
---

A lot of LINQ to XML questions on StackOverflow are being answered using `Descendants()` method calls. It looks like most of people think it’s the best way to handle and query XML document: it’s easy to use, you don’t have to worry about whole tree structure. It just works. But are these solutions really good ones? Is `Descendants()` method really that good as it seems to be? I would say: NO! I think common LINQ to XML queries should not use `Descendants()`. I’ll try to answer it shouldn’t be used in this blog post.
<!--more-->
But before I answer the question we have to say how does `Descendants()` really works and how it differs from `Elements()` method. Let’s start with MSDN description of both methods:

> `XContainer.Elements` Method (`XName`):
> Returns a filtered collection of the **child** elements of this element or document, in document order. Only elements that have a matching `XName` are included in the collection.

<!-- -->

> `XContainer.Descendants` Method (`XName`):
> Returns a filtered collection of the **descendant** elements for this document or element, in document order. Only elements that have a matching `XName` are included in the collection.

They differ by only one word: **child** in `Elements()` and **descendants** in `Descendants()`. What does it actually mean? Consider following XML document:

```xml
<?xml version="1.0"?>
<PurchaseOrder PurchaseOrderNumber="99503" OrderDate="1999-10-20">
  <Address Type="Shipping">
    <Name>Ellen Adams</Name>
    <Street>123 Maple Street</Street>
    <City>Mill Valley</City>
    <State>CA</State>
    <Zip>10999</Zip>
    <Country>USA</Country>
  </Address>
</PurchaseOrder>
```

And a simple method:

```csharp
Console.WriteLine("Descendants:");
Console.WriteLine();
foreach (var item in doc.Descendants())
    Console.WriteLine(item.Name);

Console.WriteLine();
Console.WriteLine("Elements:");
Console.WriteLine();
foreach (var item in doc.Elements())
    Console.WriteLine(item.Name);
```

I think the results are predictable:

```
Descendants:

PurchaseOrder
Address
Name
Street
City
State
Zip
Country

Elements:

PurchaseOrder
```

The difference is clear: `Descendants()` returns **all descendant element**, no matter how deep in XML tree they are. `Elements()` returns only **direct children** of current XML node. It looks simple, but **it’s really a huge difference and every LINQ to XML user has to be aware of that difference!** Why it is so important? Because it affects queries performance and can cause incorrect results when used wrong.

OK, get back to the main questions:

## Why shouldn’t you use `Descendants()` method?

### 1. Because it may have poor performance:

`Descendants()` always **traverses down whole document tree** starting from current element. It results in a set of unnecessary items being checked. As long as you’re able to precisely specify location of elements you’re looking for you should do that and use `Element()`/`Elements()` instead.

```xml
<?xml version="1.0"?>
<PurchaseOrder PurchaseOrderNumber="99503" OrderDate="1999-10-20">
  <Address Type="Shipping">
    <Name>Ellen Adams</Name>
    <Street>123 Maple Street</Street>
    <City>Mill Valley</City>
    <State>CA</State>
    <Zip>10999</Zip>
    <Country>USA</Country>
  </Address>
  <Address Type="Billing">
    <Name>Tai Yee</Name>
    <Street>8 Oak Avenue</Street>
    <City>Old Town</City>
    <State>PA</State>
    <Zip>95819</Zip>
    <Country>USA</Country>
  </Address>
  <DeliveryNotes>Please leave packages in shed by driveway.</DeliveryNotes>
  <Items>
    <Item PartNumber="872-AA">
      <ProductName>Lawnmower</ProductName>
      <Quantity>1</Quantity>
      <USPrice>148.95</USPrice>
      <Comment>Confirm this is electric</Comment>
    </Item>
    <Item PartNumber="926-AA">
      <ProductName>Baby Monitor</ProductName>
      <Quantity>2</Quantity>
      <USPrice>39.98</USPrice>
      <ShipDate>1999-05-21</ShipDate>
    </Item>
  </Items>
</PurchaseOrder>
```

Let’s query the document for all item comments. It can be easily done using `Descendants()`:

```csharp
var comments = doc.Descendants("Comment")
                    .Select(c => (string)c)
                    .ToList();
```

It produces expected results and returns a list with just one element. However, it is highly inefficient! **It will go through every XML node within whole document** (they are 27 nodes in that document) and check, if the node name matches “Comment”. Are all these checks necessary? No, they aren’t. Because we know how the document is structured, we can do following:

```csharp
var comments = doc.Root.Element("Items")
                        .Elements("Item")
                        .Elements("Comment")
                        .Select(c => (string)c)
                        .ToList();
```

It returns the same results, but it will perform much better, because e.g. it won’t even look for comments within addresses. **The bigger the file, the bigger performance gain** you get by using that approach!

### 2. Because it may produce incorrect results:

Using `Descendants()` may be risky when you’re not aware how it really works or your document structure can change in time. Consider situation, when another nodes are added into document from previous examples. But they are not item comments. They are added into addresses, e.g. to indicate preferred time of delivery:

```xml
<?xml version="1.0"?>
<PurchaseOrder PurchaseOrderNumber="99503" OrderDate="1999-10-20">
  <Address Type="Shipping">
    <Name>Ellen Adams</Name>
    <Street>123 Maple Street</Street>
    <City>Mill Valley</City>
    <State>CA</State>
    <Zip>10999</Zip>
    <Country>USA</Country>
    <Comment>After 5 P.M. only</Comment>
  </Address>
  <Address Type="Billing">
    <Name>Tai Yee</Name>
    <Street>8 Oak Avenue</Street>
    <City>Old Town</City>
    <State>PA</State>
    <Zip>95819</Zip>
    <Country>USA</Country>
  </Address>
  <DeliveryNotes>Please leave packages in shed by driveway.</DeliveryNotes>
  <Items>
    <Item PartNumber="872-AA">
      <ProductName>Lawnmower</ProductName>
      <Quantity>1</Quantity>
      <USPrice>148.95</USPrice>
      <Comment>Confirm this is electric</Comment>
    </Item>
    <Item PartNumber="926-AA">
      <ProductName>Baby Monitor</ProductName>
      <Quantity>2</Quantity>
      <USPrice>39.98</USPrice>
      <ShipDate>1999-05-21</ShipDate>
    </Item>
  </Items>
</PurchaseOrder>
```

The first query from previous example will not return correct results any more! You really should specify what you’re trying to get from XML document as precisely as possible. Using `Descendants()` is not precise at all here.

## And as an opposite: when should `Descendants()` be used?

### 1. When querying document with tree-like data:

I think it’s the case that `Descendants()` is design to be used for. File system content XML file is a great example of XML document you should definitely query using `Descendants()`:

```xml
<Dir Name="Tmp">
  <Dir Name="ConsoleApplication1">
    <Dir Name="bin">
      <Dir Name="Debug">
        <File>
          <Name>ConsoleApplication1.exe</Name>
          <Length>4608</Length>
        </File>
        <File>
          <Name>ConsoleApplication1.pdb</Name>
          <Length>11776</Length>
        </File>
        <File>
          <Name>ConsoleApplication1.vshost.exe</Name>
          <Length>9568</Length>
        </File>
        <File>
          <Name>ConsoleApplication1.vshost.exe.manifest</Name>
          <Length>473</Length>
        </File>
      </Dir>
    </Dir>
    <Dir Name="obj">
      <Dir Name="Debug">
        <Dir Name="TempPE" />
        <File>
          <Name>ConsoleApplication1.csproj.FileListAbsolute.txt</Name>
          <Length>322</Length>
        </File>
        <File>
          <Name>ConsoleApplication1.exe</Name>
          <Length>4608</Length>
        </File>
        <File>
          <Name>ConsoleApplication1.pdb</Name>
          <Length>11776</Length>
        </File>
      </Dir>
    </Dir>
    <Dir Name="Properties">
      <File>
        <Name>AssemblyInfo.cs</Name>
        <Length>1454</Length>
      </File>
    </Dir>
    <File>
      <Name>ConsoleApplication1.csproj</Name>
      <Length>2546</Length>
    </File>
    <File>
      <Name>ConsoleApplication1.sln</Name>
      <Length>937</Length>
    </File>
    <File>
      <Name>ConsoleApplication1.suo</Name>
      <Length>10752</Length>
    </File>
    <File>
      <Name>Program.cs</Name>
      <Length>269</Length>
    </File>
  </Dir>
</Dir>
```

Looking for all files with cs extension? Nothing easier than that!

```csharp
var csFiles = doc.Descendants("File")
                 .Select(f => (string)f.Element("Name"))
                 .Where(n => n.EndsWith(".cs"))
                 .ToList();
```

It would be a pain to get the same results using `Elements()` method.

To sum up, `Descendants()` is really powerful tool, and should be used with a great caution. Instead of using it everywhere you should consider changing it to `Element()`/`Elements()` calls and leave `Descendants()` for cases it’s really made for.

Do you have any other examples when `Descendants()` should/shouldn’t be used? Use comments to give your samples!