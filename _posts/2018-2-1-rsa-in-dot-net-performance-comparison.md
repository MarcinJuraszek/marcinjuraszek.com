---
layout: post
title: RSA APIs in .NET - Performance comparison
excerpt_separator: <!--more-->
---

I the last few days I had to take a closer look at cryptographic APIs available in .NET Framework.
We're using RSA + SHA256 to give Office Online hosts opportunity to validate that a request we're making is actually coming from us.
We call that [Proof Keys and you can read more about it](http://wopi.readthedocs.io/en/latest/scenarios/proofkeys.html) in public documentation on [Office Online Integration Documentation](http://wopi.readthedocs.io/en/latest/index.html).
Just recently we've noticed interesting performance problems around signing the data before we make the requests.

.NET had always had [`RSAServiceCryptoProvider`](https://docs.microsoft.com/en-us/dotnet/api/system.security.cryptography.rsacryptoserviceprovider?view=netframework-4.7.1) and that's what we were using.
However, [when .NET 4.6 shipped a new set of APIs was added](https://docs.microsoft.com/en-us/dotnet/framework/whats-new/#whats-new-in-net-2015), including [`RSACng`](https://docs.microsoft.com/en-us/dotnet/api/system.security.cryptography.rsacng?view=netframework-4.7.1).
This new RSA Api is backed by [Cryptography API: Next Generation](https://msdn.microsoft.com/en-us/library/windows/desktop/aa376210(v=vs.85).aspx) in Windows.
Turns out that new API is not just easier to use but also much faster.

<!--more-->

**I use [BenchmarkDotNet](http://benchmarkdotnet.org/) for all my benchmarks and if you're not using it too you should!**
It's really great and not just makes benchmarking easy but also makes it much easier to get meaningful results.
Turns out benchmarking and micro-benchmarking are hard to do right so it's a good idea to rely on something that has been proven instead of trying to roll your own.

To start benchmarking RSA APIs we need a certificate with a private key.
You can [create a self-signed certificate](https://social.technet.microsoft.com/Forums/windowsserver/en-US/d0bce08b-8408-4853-af20-57a6d3969656/how-do-i-create-a-self-signed-certificate-in-server-2016?forum=ws2016) if you don't have one handy.
Once we have a cert we can load it in `[GlobalSetup]` part of our benchmarks.
We also need some data to sign.
A random `byte[]` will do so I'm using `UTF8.GetBytes` on a hardcoded string to get that array.

```csharp
public X509Certificate2 Certificate;
public RSAParameters RsaParameters;
public byte[] CspBlob;

private static readonly byte[] DataToSign
    = Encoding.UTF8.GetBytes("some string to get bytes from for signing, because why not!");

[GlobalSetup]
public void Setup()
{
    Certificate = new X509Certificate2("Certificate", "Password", X509KeyStorageFlags.Exportable);
    RsaParameters = Certificate.GetRSAPrivateKey().ExportParameters(includePrivateParameters: true);
    CspBlob = ((RSACryptoServiceProvider)Certificate.PrivateKey).ExportCspBlob(includePrivateParameters: true);
}
```

I'm storing the certificate data in multiple formats to see if there is any performance difference based on how `RSACryptoServiceProvider` and `RSACng` are created.

Now that these are available let's see what we're going to benchmark.
`RSACryptoServiceProvider` first.

You can import data into `RSACryptoServiceProvider` using `RSAParameters` and CSP Blob so let's test both and make one of them our baseline.

```csharp
[Benchmark(Baseline = true)]
public byte[] SignUsingRSACryptoServiceProviderFromRsaParameters()
{
    using (RSACryptoServiceProvider rsaAlg = new RSACryptoServiceProvider())
    {
        rsaAlg.ImportParameters(RsaParameters);
        return rsaAlg.SignData(DataToSign, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
    }
}

[Benchmark]
public byte[] SignUsingRSACryptoServiceProviderFromCspBlob()
{
    using (RSACryptoServiceProvider rsaAlg = new RSACryptoServiceProvider())
    {
        rsaAlg.ImportCspBlob(CspBlob);
        return rsaAlg.SignData(DataToSign, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
    }
}
```

There is also another approach.
Instead of passing `HashAlgorithmName` into `SignDate` you can pass an instance of `HashAlgorithm`.
There shouldn't be much of a difference but you never know until you benchmark so let's add two more benchmarks.

```csharp
[Benchmark]
public byte[] SignUsingRSACryptoServiceProviderFromRsaParametersWithHashAlgorithm()
{
    using (RSACryptoServiceProvider rsaAlg = new RSACryptoServiceProvider())
    {
        rsaAlg.ImportParameters(RsaParameters);
        using (SHA256CryptoServiceProvider hashAlg = new SHA256CryptoServiceProvider())
        {
            return rsaAlg.SignData(DataToSign, hashAlg);
        }
    }
}

[Benchmark]
public byte[] SignUsingRSACryptoServiceProviderFromCspBlobWithHashAlgorithm()
{
    using (RSACryptoServiceProvider rsaAlg = new RSACryptoServiceProvider())
    {
        rsaAlg.ImportCspBlob(CspBlob);
        using (SHA256CryptoServiceProvider hashAlg = new SHA256CryptoServiceProvider())
        {
            return rsaAlg.SignData(DataToSign, hashAlg);
        }
    }
}
```

OK. That's it for `RSACryptoServiceProvider`.
On to the new stuff - `RSACng`.
It's recommended to get an instance of `RSA`-derived class by calling `X509Certificate.GetRSAPrivateKey`.
When CNG is available on the machine it will return an instance of `RSACng` and fallback to `RSACryptoServiceProvider` if it's not.

```csharp
[Benchmark]
public byte[] SignUsingRSACngFromGetRSAPrivateKey()
{
    using (RSA rsaAlg = Certificate.GetRSAPrivateKey())
    {
        return rsaAlg.SignData(DataToSign, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
    }
}
```

I also want to test how `RSACng` performs when it's provided with `RSAParameters` so that's another benchmark.

```csharp
[Benchmark]
public byte[] SignUsingRSACngFromRSAParameters()
{
    using (RSA rsaAlg = new RSACng())
    {
        rsaAlg.ImportParameters(RsaParameters);
        return rsaAlg.SignData(DataToSign, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
    }
}
```

`RSA` and `RSACng` do not expose `SignData` which takes a `HashAlgorithm` instance so I won't be testing `RSACng` with `SHA256CryptoServiceProvider`.
That seems like enough tests to get a nice picture of what's happening.

Here are the results:

```
                                                              Method |     Mean |     Error |    StdDev | Scaled |
-------------------------------------------------------------------- |---------:|----------:|----------:|-------:|
                  SignUsingRSACryptoServiceProviderFromRsaParameters | 7.702 ms | 0.0484 ms | 0.0429 ms |   1.00 |
                        SignUsingRSACryptoServiceProviderFromCspBlob | 7.760 ms | 0.1352 ms | 0.1265 ms |   1.01 |
 SignUsingRSACryptoServiceProviderFromRsaParametersWithHashAlgorithm | 7.754 ms | 0.0694 ms | 0.0649 ms |   1.01 |
       SignUsingRSACryptoServiceProviderFromCspBlobWithHashAlgorithm | 7.760 ms | 0.0684 ms | 0.0640 ms |   1.01 |
                                 SignUsingRSACngFromGetRSAPrivateKey | 3.926 ms | 0.0782 ms | 0.0930 ms |   0.51 |
                                    SignUsingRSACngFromRSAParameters | 2.127 ms | 0.0340 ms | 0.0301 ms |   0.28 |
```

Wow! **`RSACng` is between 50 and 70% faster than `RSACryptoServiceProvider`!**
That's quite good.
Based on these results we're definitely switching to CNG-backed cryptography and **you should too**!

If you have an option you should probably use `RSAParameters` to get that additional 20% improvement.
From what I explored today **that will require the certificate to be loaded from file**, so if you're instead loading it from Windows Certificate Store you might have to stick to `GetRsaPrivateKey`.
50% is still quite an improvement anyway, isn't it?

The results also show that for `RSACryptoServiceProvider` there is no difference between passing in `HashAlgorithmName.SHA256` or an instance of `SHA256CryptoServiceProvider`.
If there is no difference than I'd recommend using whichever version you find easier to read.
Of course, if you try pooling `SHA256CryptoServiceProvider` instance that might change, so if that's something you're considering you should benchmark it before investing in an Object Pool.