---
layout: post
title: ASP.NET Core configuration when running as Service Fabric service
excerpt_separator: <!--more-->
---

When you create an ASP.NET Core Stateless Service for Service Fabric an `appsettings.json` file is added automatically as part of the project template.
It might surprise you, but if **you run the template service the settings from that file won't be available for you to use in the code!**
In this post I'll show you how to make the service respect that file and allow you access the config values from it.
I'll also talk about the difference between loading the `appsettings.json` file from Code or Config package and why you might care.
<!--more-->

Let's start by adding an empty **Stateless ASP.NET Core** service to a Service Fabric application.
I'm targetting full .NET Framework, but the same applies to a service running against .NET Core.

![New Stateless ASP.NET Core service - screen 1](../../images/service-fabric-asp-net-core-config/new-stateless-asp-net-core-service.PNG)

![New Stateless ASP.NET Core service - screen 2](../../images/service-fabric-asp-net-core-config/new-stateless-asp-net-core-service-2.PNG)

I selected an API template here without any Authentication for simplicity, but there is a bigger issue if you need proper authentication.
If you were to try using AAD-based auth in your service the template would add the AAD-related settings to `appsettings.json`, which as I said are not properly accessible from the service code.
Running a service with AAD auth would result in `ArgumentNullException` and `InvalidServerError` returned by any route with authentication enabled.
There is a support ticket tracking that on *Developer Community* website: [New Stateless ASP.NET Core Service Fabric Service with Azure AD Authentication throws ArgumentNull exception on start up](https://developercommunity.visualstudio.com/content/problem/349366/new-stateless-aspnet-core-service-fabric-service-w.html).
You can fix that by following the steps in this blog post!

To show you what I mean by *the settings are not available in the code* let's put a breakpoint in `Startup` class constructor and see what `configuration` we have available there:

![Configuration details - before](../../images/service-fabric-asp-net-core-config/configuration-details.PNG)

As you can see all that you get by default is coming from the environment variables (see `EnvironmentVariablesConfigurationProvider` being the only used provider).
**`appsettings.json` is not used at all!**

## How can we fix it?

Turns out it's fairly easy.
All we need is manually add a `JsonConfigurationProvider` instance to the `ConfigurationBuilder` during initialization.
The easiest way to do that is by modifying the `WebHost` setup in `CreateServiceInstanceListener` method of our service definition (in my sample that's `CreateServiceIn `StatelessAspNetCore` class):

```cs
protected override IEnumerable<ServiceInstanceListener> CreateServiceInstanceListeners()
{
    return new ServiceInstanceListener[]
    {
        new ServiceInstanceListener(serviceContext =>
            new KestrelCommunicationListener(serviceContext, "ServiceEndpoint", (url, listener) =>
            {
                ServiceEventSource.Current.ServiceMessage(serviceContext, $"Starting Kestrel on {url}");

                return new WebHostBuilder()
                            .UseKestrel()
                            .ConfigureAppConfiguration((builderContext, config) =>
                            {
                                config.AddJsonFile("appsettings.json", optional: false, reloadOnChange: true);
                            })
                            .ConfigureServices(
                                services => services
                                    .AddSingleton<StatelessServiceContext>(serviceContext))
                            .UseContentRoot(Directory.GetCurrentDirectory())
                            .UseStartup<Startup>()
                            .UseServiceFabricIntegration(listener, ServiceFabricIntegrationOptions.None)
                            .UseUrls(url)
                            .Build();
            }))
    };
}
```

The important part of here:

```cs
.ConfigureAppConfiguration((builderContext, config) =>
{
    config.AddJsonFile("appsettings.json", optional: false, reloadOnChange: true);
})
```

It adds the `appsettings.json` file to the configuration chain, which we can confirm after restarting the service and checking the same `configuration` object in `Startup` class constructor:

![Configuration details - after](../../images/service-fabric-asp-net-core-config/configuration-details-after.PNG)

We have a new provider, which adds two more settings - exactly what's in the default `appsettings.json` file:

```json
{
  "Logging": {
    "LogLevel": {
      "Default": "Warning"
    }
  },
  "AllowedHosts": "*"
}
```

### Code vs. Config package

With the code change I talked about above the `appsettings.json` file is deployed as part of the Code Package.
That means that we won't be able to change the values without restarting the service.
For some settings that's ok, or maybe ever desirable.
For other it would be better if we were able to update them without restarting the service.
To do that we have to move `appsettings.json` file to Config package and update the configuration to read it from there, with an automatic reload on every change.

Moving the file from Code package to Config package is as easy as moving it around in the Solution Explorer:

![Project structure change to move appsettings.json from Code to Config package](../../images/service-fabric-asp-net-core-config/project-structure-change.PNG)

The change in `ConfigureAppConfiguration` is a bit more involved.
We have to somehow get the path to the Config package directory and craft a file path to `appsettings.json` file which we expect to be there now.
To make it cleaner let's create a helper extension method to do all that:

```cs
public static class ServiceFabricConfigurationExtensions
{
    public static IConfigurationBuilder AddJsonFile(this IConfigurationBuilder builder, ServiceContext serviceContext)
    {
        // get the Config package directory
        var configFolderPath = serviceContext.CodePackageActivationContext.GetConfigurationPackageObject("Config").Path;
        // combine it with appsettings.json file name
        var appSettingsFilePath = System.IO.Path.Combine(configFolderPath, "appsettings.json");
        // add to the builder, making sure it will be reloaded every time the file changes, e.g. during Config-only deployment
        builder.AddJsonFile(appSettingsFilePath, optional: false, reloadOnChange: true);
        // return the builder to allow for call chaining a.k.a. fluent api
        return builder;
    }
}
```

With that we can update our `ConfigureAppConfiguration` call to use the new extension method:

```cs
.ConfigureAppConfiguration((builderContext, config) =>
{
    config.AddJsonFile(serviceContext);
})
```

And with this one method call we added regular `appsettings.json` config file as a configuration source which will be reloaded every time it changes.
