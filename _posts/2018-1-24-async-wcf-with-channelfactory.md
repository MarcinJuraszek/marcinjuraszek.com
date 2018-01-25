---
layout: post
title: Calling a synchronous WCF method asynchronously using ChannelFactory
excerpt_separator: <!--more-->
---

[Asynchronous operation contracts in WCF](https://docs.microsoft.com/en-us/dotnet/framework/wcf/synchronous-and-asynchronous-operations) have been supported since .NET 4.5: you can define service methods to return `Task` or `Task<T>` and as you implement your service logic you can use `async`/`await` to *do the right things* when it comes to using IO or other asynchronous operation.
You can also use older paradigm called Asynchronous Programming Model (APM) which is based on a pair of `Begin*`/`End*` methods. 

On the consumer side you can use Visual Studio's "*Add Service Reference*" option to generate a client or use `ChannelFactory` and the service interface to make the calls.
All that sounds pretty great, until you run into a situation I recently run into: you have **a WCF service which has method you want to implement asynchronously**, but you also have some legacy **client which for a valid reason has to make the calls in synchronous way**.
In this post I'll show you how to call asynchronous WCF operation synchronously (or the other way around) using `ChannelFactory`.

<!--more-->

Let's begin with a simple service definition with just one, synchronous method.

```cs
[ServiceContract]
public interface IFooService
{
    [OperationContract]
    string GetFoo(int value);
}
```

It's quite simple to call an endpoint implementing this interface using `ChannelFactory`.
You need access to that interface and a URL on which the service is listening:

```cs
var factory = new ChannelFactory<IService2>(new BasicHttpBinding());
var channel = factory.CreateChannel(new EndpointAddress("http://localhost:51109/FooService.svc"));
var data = channel.GetData(22);
```

`ChannelFactory<T>.CreateChannel` returns an object which implements `T`, which means that in the case above `channel` implements `IFoo`.
That's why I can call `GetData()` on it.
Behind the scenes a network call to provided endpoint address will be made, serialization/deserialization of request/response data will be handled, etc.

Both the client and the service are tied to that single interface, so if I were to decide that the service needs to do some IO as a result of that request I would have to change the contract to allow for that IO to be done in an asynchronous way:

```cs
[ServiceContract]
public interface IFooService
{
    [OperationContract]
    Task<string> GetFooAsync(int value);
}
```

Unfortunately, **that will leak the asynchronous nature of the server implementation to the client** - now it also has to deal with `Task<string>` instead of just `string` instance.
You could say, that no matter what the client should make the calls asynchronously because it involved a network call.
However, that's not always possible, especially when you're dealing with legacy applications.
In my recent scenario the legacy client had a very complicated concurrency model and many of the WCF calls were made from within `lock` statements.
I know that's a red flag, but let's ignore that for now.
You can't `await` within a C# `lock`, which is quite problematic.
You could simply update the contract to use `Task<T>` and in the client code use `Result`, `Wait` or `GetAwaiter().GetResult()` to synchronously wait for the results, but that also might be risky, especially when the client is an ASP.NET application.
In that case [you're risking deadlocks](http://blog.stephencleary.com/2012/07/dont-block-on-async-code.html).

You can also face an opposite situation - you have a legacy WCF service which implements all the operations synchronously.
You're writing a new client to that service and you'd like it to use `async`/`await` when doing the WCF calls.
There are at least a few question on how to do that on StackOverflow (eg [this one](https://stackoverflow.com/questions/36278513/implementing-async-await-pattern-for-manually-generated-wcf-client-side-proxie)) so it can't be that rare to run into that problem.

The solution I came up with uses that fact, that **WCF behind the scenes exposes every operation is two ways - synchronously and asynchronously**.
That's why *Add Service Reference* can generate asynchronous clients on synchronous services.
You can see that when using *WCF Test Client*.
Even though my `IFooService` interface defines only one method: `GetFoo`, *WCF Test Client* shows an extra method: `GetFooAsync`:

![Bind error in VS](../../images/wcf-async/wcf-test-client.png)

You can also run into that realization if you try to manually implement both synchronous and asynchronous methods in your service.
Let's say both `GetFoo` and `GetFooAsync` were defined in `IFooService`:

```cs
[ServiceContract]
public interface IFooService
{
    [OperationContract]
    string GetFoo(int value);

    [OperationContract]
    Task<string> GetFooAsync(int value);
}
```

If you try running this service you'll see a following error:

> Cannot have two operations in the same contract with the same name, methods `GetFooAsync` and `GetFoo` in type `WcfService.IFooService` violate this rule. You can change the name of one of the operations by changing the method name or by using the Name property of OperationContractAttribute. 

**From WCFs perspective `GetFooAsync` and `GetFoo` are the same method!**

We can *abuse* that to get what we want - an ability to call an asynchronous WCF operation synchronously.
The same technique can be used to achieve the opposite - call a synchronous WCF operation asynchronously.

To do that we can define a second interface, which mimics the service contract but changes the method to be asynchronous

```cs
[ServiceContract]
public interface IFooService
{
    [OperationContract]
    string GetFoo(int value);
}

[ServiceContract]
public interface IFooServiceAsync
{
    [OperationContract]
    Task<string> GetFooAsync(int value);
}
```

It feels like it would work, but there is one thing that's missing.
WCF uses the interface name as the default value for the name of the service.
It also requires the name on the request to match on the service endpoint.
In that case they don't - the service exposes `IFooService` endpoint but the caller sends a request addressed to `IFooServiceAsync`.
That will cause exceptions when trying to make the call.

> `System.ServiceModel.ActionNotSupportedException`: 'The message with Action 'http://tempuri.org/IFooServiceAsync/GetFoo' cannot be processed at the receiver, due to a ContractFilter mismatch at the EndpointDispatcher. This may be because of either a contract mismatch (mismatched Actions between sender and receiver) or a binding/security mismatch between the sender and the receiver.  Check that sender and receiver have the same contract and the same binding (including security requirements, e.g. Message, Transport, None).'

There is an easy fix for that.
You can override the default name by providing it to `ServiceContract` attribute constructor.

```cs
[ServiceContract(Name = "IFooService")]
public interface IFooServiceAsync
{
    [OperationContract]
    Task<string> GetFooAsync(int value);
}
```

**With that we can use one interface when implementing the service and the other one when calling into it and things will just work!**
These two interfaces don't have to be in the same namespace or dll, which makes the entire thing much easier.

To show you that it works I created a WCF service with two methods, one of which returns `string` directly and another one returning `Task<string>`:

```cs
namespace WcfService
{
    [ServiceContract]
    public interface IFooService
    {
        [OperationContract]
        string GetFoo(int value);

        [OperationContract]
        Task<string> GetBarAsync();
    }
}
```

Service implementation is really simple:

```cs
namespace WcfService
{
    public class FooService : IFooService
    {
        public string GetFoo(int value)
        {
            return string.Format("You entered: {0}", value);
        }

        public Task<string> GetBarAsync()
        {
            return Task.FromResult("Bar!");
        }
    }
}
```

That's all there is on the server side.

On the client I have a simple console application which tries to call into these methods.
However, it tries to call the `string`-returning method asynchronously, and the `Task<string>` method synchronously; all using `ChannelFactory`.

For that I created a second interface, within the client code with updates method:

```cs
namespace ConsoleApp1
{
    [ServiceContract(Name = "IFooService")]
    public interface IFooServicePretender
    {
        [OperationContract]
        Task<string> GetFooAsync(int value);

        [OperationContract]
        string GetBar();
    }
}
```

And a simple `Main` method trying to call into these 2 methods:

```cs
class Program
{
    static async Task Main(string[] args)
    {
        var factory = new ChannelFactory<IFooServicePretender>(new BasicHttpBinding());
        var channel = factory.CreateChannel(new EndpointAddress("http://localhost:51109/FooService.svc"));

        var fooResult = await channel.GetFooAsync(12345);
        var barResult = channel.GetBar();

        Console.WriteLine("GetFooAsync result: " + fooResult);
        Console.WriteLine("GetBar result: " + barResult);
    }
}
```

After starting up the service I can run the console application and get the expected results:

```
GetFooAsync result: You entered: 12345
GetBar result: Bar!
Press any key to continue . . .
```

That proves that the idea works and allows you to decouple the client from the server and make one asynchronous when the other one is implemented synchronously, even when using `ChannelFactory`.

The code is available on GitHub at [MarcinJuraszek/SyncAsyncWcfChannelFactorySample](https://github.com/MarcinJuraszek/SyncAsyncWcfChannelFactorySample).