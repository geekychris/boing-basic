Option Explicit
Dim news As Http, weather As Http
Set news = CreateObject("Http")
Set weather = CreateObject("Http")
news.OnDone = "NewsDone"
weather.OnDone = "WeatherDone"
news.GetAsync "https://example.com/news.json"
weather.GetAsync "https://example.com/weather.json"
Do While news.Busy Or weather.Busy
    DoEvents
Loop

Sub NewsDone()
    Print "news:"; news.Status; news.BytesReceived
End Sub

Sub WeatherDone()
    Print "weather:"; weather.Status; weather.BytesReceived
End Sub
