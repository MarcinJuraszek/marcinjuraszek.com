---
layout: post
title: ASP.NET Identity 2.0.0 – UserName and Email separation
excerpt_separator: <!--more-->
---

The release of new version of ASP.NET Identity – [ASP.NET Identity 2.0.0](http://blogs.msdn.com/b/webdev/archive/2014/03/20/test-announcing-rtm-of-asp-net-identity-2-0-0.aspx) comes with new sample project, which shows how all the new features like email confirmation, password recovery and two-factor authentication can be used while creating web applications. However, the new sample follows an approach which sometime is not acceptable: **it uses an email address as user name**. In my case, I need these data to be separated, and that’s why I decided to modify sample project to allow that.

<!--more-->

## Model

ASP.NET Identity Sample project uses `Microsoft.AspNet.Identity.EntityFramework.IdentityDbContext<TUser>` and because of that, I don’t have to make any changes in the model! Default one already contains two separate fields for `UserName` and `Email`. So sad, that by default they both contain exact same values.

## Views, ViewModels and AccountController

Knowing that **default model is already ready for username and email separation**, we can move forward and update the views, view models and AccountController.

### Registration

Starting with the registration page, lets extend sample code in all necessary places:

#### RegistrerViewModel class

```csharp
public class RegisterViewModel {

    [Required]
    [Display(Name = "UserName")]
    public string UserName { get; set; }
    // (...)
```

#### Register.cshtml view

```xml
<!-- (...) -->
<div class="form-group">
    @Html.LabelFor(m => m.UserName, new { @class = "col-md-2 control-label" })
    <div class="col-md-10">
        @Html.TextBoxFor(m => m.UserName, new { @class = "form-control " })
    </div>
</div>
<!-- (...) -->
```

#### AccountController.Register(RegisterViewModel model) method

```csharp
// (...)
var user = new ApplicationUser { UserName = model.UserName, Email = model.Email };
// (...)
```

With these changes we now have additional field on registration page:

![Registration form](../../images/asp-net-identity/Registration.png)

We can also confirm that registration works fine and both email and username are being saved looking into the database used by our application:

![Database view](../../images/asp-net-identity/UsersTable.png)

ASP.NET Identity also **checks that username is unique** when user is trying to register and shows appropriate error message when you try register with already taken username:

![Uniqueness](../../images/asp-net-identity/UserNameDuplication.png)

### Login page

Everything seems to work fine, but when you try to log with changes like that, you’ll find out it’s not possible. That’s because although login page requires an email address to log in it actually uses `model.UserName` to validate provided email. With our changes **`model.UserName` does not contain email anymore**. But that problem can be fixed easily.


#### LoginViewModel class

```csharp
public class LoginViewModel {
    [Required]
    [Display(Name = "User Name")]
    public string UserName { get; set; }

    [Required]
    [DataType(DataType.Password)]
    [Display(Name = "Password")]
    public string Password { get; set; }

    [Display(Name = "Remember me?")]
    public bool RememberMe { get; set; }
}
```

#### Login.cshtml view

```xml
                <!-- (...) -->
                <div class="form-group">
                    @Html.LabelFor(m => m.UserName, new { @class = "col-md-2 control-label" })
                    <div class="col-md-10">
                        @Html.TextBoxFor(m => m.UserName, new { @class = "form-control" })
                        @Html.ValidationMessageFor(m => m.UserName, "", new { @class = "text-danger" })
                    </div>
                </div>
                <!-- (...) -->
```

#### AccountController.Login(LoginViewModel model, string returnUrl) method

```csharp
[HttpPost]
[AllowAnonymous]
[ValidateAntiForgeryToken]
public async Task<ActionResult> Login(LoginViewModel model, string returnUrl)
{
    if (!ModelState.IsValid)
    {
        return View(model);
    }

    // This doesn't count login failures towards lockout only two factor authentication
    // To enable password failures to trigger lockout, change to shouldLockout: true
    var result = await SignInHelper.PasswordSignIn(model.UserName, model.Password, model.RememberMe, shouldLockout: false);
    switch (result)
    {
    // (...)
```

There changes allow us to log in using username instead of email.

![Loging form](../../images/asp-net-identity/LogIn.png)

If you’d like to provide option to log in with username or email, check this post: [ASP.NET Identity 2.0 – Logging in with Email or Username](http://anthonychu.ca/post/aspnet-identity-20---logging-in-with-email-or-username). After logging in you can see that your **username is shown on the right side of top navigation bar**. By default there is an email shown there instead.

![Top-bar](../../images/asp-net-identity/topbar.png)

###Password recovery

Another part of account management we’re going to work on is password recovery feature. To make it safer **lets make both username and email address required on Forgot Password page**.

#### ForgotPasswordViewModel class

```csharp
public class ForgotPasswordViewModel {
    [Required]
    [Display(Name = "User Name")]
    public string UserName { get; set; }

    [Required]
    [EmailAddress]
    [Display(Name = "Email")]
    public string Email { get; set; }
}
```

#### ForgotPassword.cshtml view

```xml
<!-- (...) -->
<h4>Enter your username and email.</h4>
<hr />
@Html.ValidationSummary("", new { @class = "text-danger" })
<div class="form-group">
    @Html.LabelFor(m => m.UserName, new { @class = "col-md-2 control-label" })
    <div class="col-md-10">
        @Html.TextBoxFor(m => m.UserName, new { @class = "form-control" })
    </div>
</div>
<!-- (...) -->
```

#### AccountController.ForgotPassword() method

```csharp
public async Task<ActionResult> ForgotPassword(ForgotPasswordViewModel model)
{
    if (ModelState.IsValid)
    {
        // search for user by username first
        var user = await UserManager.FindByNameAsync(model.UserName);
                
        // check email address
        if (user == null || !(await UserManager.IsEmailConfirmedAsync(user.Id))
            || (await UserManager.GetEmailAsync(user.Id)) != model.Email)
        {
            // Don't reveal that the user does not exist or is not confirmed
            return View("ForgotPasswordConfirmation");
        }
        // (...)
```

And now all necessary scenarios uses both UserName and Email address, with separate values.