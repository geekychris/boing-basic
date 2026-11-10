Dim web As Http
Set web = New Http
web.SetCookie "theme", "dark", "example.com"
web.SetCookie "lang", "en", "example.com", "/docs"
Print web.CookieCount; "cookies; theme = "; web.GetCookie("theme", "example.com")
Print Replace(web.Cookies, vbTab, " | ");
web.ClearCookies
Print web.CookieCount; "after ClearCookies"
