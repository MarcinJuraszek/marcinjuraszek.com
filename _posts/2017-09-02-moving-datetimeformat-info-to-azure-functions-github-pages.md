---
layout: post
title: Moving datetimeformat.info to Azure Functions and GitHub Pages
excerpt_separator: <!--more-->
---

I created [datetimeformat.info](https://datetimeformat.info) couple years ago when I got tired of googling what the right custom format string for `DateTime.ToString()` method is.
It used to be a simple ASP.NET site and I hosted it as an Azure Web App.
The problem is, hosting it on Azure wasn't cheap.
datetimeformat.info does not get much traffic, there is minimal amount of logic there but because I hosted it on a single B1 Basic instance I used to spend ~$55 a month.
Sure, I can pack multiple other websites and applications on the same instance and that money is something I get as part of my MSDN subscription anyway, but still, it felt wrong.
That's why today I updated it to use GitHub pages to serve static content and Azure Functions to provide required API.
New cost of running the site: $0 (yes, zero!).

<!--more-->

## Azure Functions

The very first thing I did was creating an Azure Functions application to move my API to.
The API is very simple - it's just a single method taking time and format string and returning that same time formatted using that format string.
Nothing really fancy.

I reused most of the code, beginning with classes describing my request/response data model:

```csharp
public class FormatResult
{
    public string FormattedValue { get; set; }
    public Error Error { get; set; }
}

public class Error
{
    public string Message { get; set; }
    public string ExceptionName { get; set; }
}

public class FormatRequest
{
    public string Value { get; set; }
    public string Pattern { get; set; }
}
```

I created the function using **HttpTrigger - C#** template with *Authorization level* set to *Anonymous*.

Azure Functions assign an HTTP endpoint to each function which, whenever a request is sent to it, will trigger the code.
`HttpRequestMessage` gives me access to the request content, which can be easily deserialized, processed and correct response can be returned to the caller.
The entire logic of my endpoint is just a single function with simple signature:

```csharp

public static async Task<HttpResponseMessage> Run(HttpRequestMessage req, TraceWriter log)
{
    // deserialize content to FormatRequest
    var formatRequest = await TryDeserializeRequest(req, log);

    // make sure both value and pattern were provided
    if (string.IsNullOrEmpty(formatRequest?.Value) || string.IsNullOrEmpty(formatRequest?.Pattern))
    {
        return req.CreateResponse(HttpStatusCode.BadRequest);
    }

    return req.CreateResponse(GetResponse(formatRequest));
}
```

### Referencing packages

Now, as you can see some of the logic is extracted to helper methods, but believe me when I say there is nothing complicated there either.
Azure Functions allow you to easily reference packages, which is great because it allowed me to use *Newtonsoft.Json* for deserialization/serialization.
All I had to do is add a reference and a using statement:

```csharp
#r "Newtonsoft.Json"

using System.Globalization;
using System.Net;
using Newtonsoft.Json;
```

That's pretty neat.

I won't paste the entire code here, but you can find it on GitHub: [Format.csx](https://github.com/MarcinJuraszek/DateTimeFormatInfo/blob/master/functions/Format.csx).

### Testing the function

The interface in Azure Portal allows you for easy testing of your logic too.
You can send requests to the function from within the UI, see log output and the response returned from your brand new endpoint.
With that I was able to code the entire thing in the browser, without any issues.
If the code doesn't compile output windows will also show you the compilation errors to make iterating on function logic easier.

![Azure Functions UI in Azure Portal](../../images/datetimeformat-info-azure-functions/azure-functions-ui.png)

If you don't want to use the UI you can also precompile your functions locally and deploy them as dlls. See [Using .NET class libraries with Azure Functions](https://docs.microsoft.com/en-us/azure/azure-functions/functions-dotnet-class-library) for details on that.

## GitHub Pages

With my Azure Function running and my logic exposed as an HTTP endpoint I moved to migrating my static resources to GitHub pages.
All I had to do is remove all ASP.NET stuff - web.config, WebAPI controllers, etc.
Because I didn't need any server-side logic anymore all that was left was a single html file, single css file and couple JavaScript files.
I also updated the JavaScript to point at the HTTP endpoint my function is exposed at.

Once I merged it to master branch in my GitHub repo I was ready to enabled GitHub pages feature in repository settings.
I made sure to specify my custom domain and pointed at `/docs` folder in my master branch as the place where my site content is:

![GitHub Pages configuration for DateTimeFormat.Info](../../images/datetimeformat-info-azure-functions/github-pages.png)

I also updated my DNS records to point at GitHub servers instead of the IPs I used for Azure-hosted website.
You can find instructions on how to configure that in GitHub documentation: [Using a custom domain with GitHub Pages](https://help.github.com/articles/using-a-custom-domain-with-github-pages/).

Once the DNS change propagated I could see my page being served from GitHub!
How did I know that was the case?
Because it didn't work :)

![DateTimeFormat.Info not working because of CORS](../../images/datetimeformat-info-azure-functions/datetimeformat-info-error.png)

Where that large black dash is a properly-formatted DateTime instance should be displayed instead.
Developer Tools in my browser clearly showed that a request to my function was triggered, but was being blocked because of CORS restriction:

```
XMLHttpRequest cannot load https://datetimeformatinfoapi.azurewebsites.net/api/Format. No 'Access-Control-Allow-Origin' header is present on the requested resource. Origin 'https://datetimeformat.info' is therefore not allowed access.
```

## Enabling CORS on Azure Function

Turns out by default Azure Functions are not CORS-enabled.
But that's something you can turn on for the domains you expect to be targeting your functions, or even enable it to be used from any website by specifying `'*'` as the allowed origin.

To do so click on the name of the functions app your function is part of and go to **Platform Features** tab.
Once there you'll find **CORS** option which will open a new panel where you can configure allowed origins for your functions app.

![Platform Features tab for Azure Functions App](../../images/datetimeformat-info-azure-functions/azure-functions-platform-features.png)

That configuration is bound to the functions app, so adding or removing a domain there will affect all the functions in that app.
I simply added *http://datetimeformat.info* and *https://datetimeformat.info* to the list, saved and it had an immediate effect.

![CORS configuration for Azure Functions App](../../images/datetimeformat-info-azure-functions/azure-functions-cors.png)

Now, when going to http://datetimeformat.info I can see the page working as expected:

![DateTimeFormat.Info working correctly again!](../../images/datetimeformat-info-azure-functions/datetimeformat-info-ok.png)

## Summary

So, with about 30 minutes of work I was able to move the entire website from Azure Web App to GitHub Page and Azure Functions combination.
The entire experience was super nice and I can see why people are really excited about the possibilities Azure Functions and serverless computing in general enables.
And I almost forgot - I can use the $55 I saved by retiring one of my App Services instances on more fun stuff :)


