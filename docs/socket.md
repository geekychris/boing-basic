# Socket: TCP and UDP networking

`Socket` is a built-in class for talking to other programs over the network: a client for a
line-based protocol, a small server, a chat between two Amigas, game state over UDP. It works on
AmigaOS 4 (bsdsocket.library, Roadshow) and on the host (macOS/Linux), with the same behaviour.

A socket can be used two ways, and a program can mix them:

- **Waiting calls.** `Connect`, `Send`, `Read`, `ReceiveLine` and `Accept` wait until they are
  done, at most `Timeout` milliseconds. Easy for console programs and simple clients.
- **Events.** Declare the variable `WithEvents` and write handlers: `link_Connect`,
  `link_DataArrival`, `link_Close`... In a form program they arrive through the window's event
  loop, like a button's Click, so the window stays responsive while the network works.

```basic
Dim web As Socket
Set web = CreateObject("Socket")
web.Connect "example.com", 80
web.Send "HEAD / HTTP/1.0" & vbCrLf & "Host: example.com" & vbCrLf & vbCrLf
Print web.ReceiveLine()            ' HTTP/1.0 200 OK
web.Close
```

## Making a socket

`Set s = CreateObject("Socket")` (or `CreateObject("Boing.Socket")`). A new socket is closed;
`Connect`, `Listen` or `Bind` opens it as a TCP client, a TCP server or a UDP socket. `Close`
closes it and it can be opened again. A socket is also closed when the last reference to it
goes away.

## TCP clients

| Method | |
|---|---|
| `Connect host, port` | connects to a host name or address. Without events it waits until connected (at most `Timeout`); with events it returns at once and `Connect` (or `Error`) fires later. |
| `Send data` | sends all the bytes of a String (binary is fine), waiting while the network is busy (at most `Timeout`). If the socket is still connecting, it waits for the connection first. |
| `SendLine text` | `Send text & vbCrLf` |
| `Receive([maxBytes])` | what has arrived so far (up to maxBytes), without waiting. "" when nothing is there. |
| `Peek([maxBytes])` | like `Receive`, but leaves the data in place |
| `Read(count)` | waits until count bytes have arrived and returns them; fewer only when the other side closed. Error 31104 after `Timeout`. |
| `ReceiveLine()` | waits for a line ending in LF (a CR before it is dropped) and returns it without the line end. When the other side has closed, returns the rest and then "". Error 31104 after `Timeout`. |
| `BytesAvailable` | how many bytes can be read now |
| `AtEnd` | True when the other side has closed and everything has been read |
| `Close` | closes the connection |

```basic
Do Until s.AtEnd
    Print s.ReceiveLine()
Loop
```

## TCP servers

| Method | |
|---|---|
| `Listen port [, address]` | waits for connections on port (0: any free port; read it back from `LocalPort`). address limits it to one interface, e.g. `"127.0.0.1"` for this machine only; default all. |
| `Accept([waitMs])` | takes a waiting connection and returns it as a new, connected Socket, or `Nothing` when none came within waitMs (default `Timeout`; 0: don't wait). |

```basic
Dim server As Socket, client As Socket
Set server = CreateObject("Socket")
server.Listen 7000
Do
    Set client = server.Accept(60000)
    If Not client Is Nothing Then
        client.SendLine "Hello from the Amiga, " & client.RemoteHost
        client.Close
    End If
Loop
```

## UDP

| Method | |
|---|---|
| `Bind port [, address]` | opens a UDP socket on port (0: any free one) |
| `SendTo host, port, data` | sends one datagram. On a socket that isn't open yet, it opens a UDP socket on any free port first. |
| `ReceiveFrom([waitMs])` | the next datagram ("" if none came within waitMs, default 0); `RemoteHost` and `RemotePort` then say who sent it |
| `BytesAvailable` | the size of the next datagram |

Datagrams can be lost or arrive out of order, and each `SendTo` is one datagram (keep them under
about 1400 bytes to stay in one network packet).

## Properties

| Property | |
|---|---|
| `State` | `sockClosed` (0), `sockOpen` (1, UDP), `sockListening` (2), `sockConnecting` (6), `sockConnected` (7), `sockClosing` (8: the other side closed; data may still be waiting), `sockError` (9: the connection failed) |
| `Connected` | True while connected |
| `RemoteHost`, `RemotePort` | the other side (for UDP, the sender of the last datagram read) |
| `LocalHost`, `LocalPort` | this side's address and port |
| `MachineAddress` | this machine's IPv4 address on the network (the one others use to reach it; "127.0.0.1" without a network) |
| `Timeout` | milliseconds the waiting calls wait; default 30000 |
| `Protocol` | "TCP" or "UDP" |
| `Tag` | any value the program wants to keep with the socket (a user name, say) |

## Events

Declare the socket `WithEvents` at module level (or in a class) and write subs named
`<variable>_<event>`:

| Event | When |
|---|---|
| `Connect()` | a `Connect` with events has succeeded |
| `Error(ByVal Number As Long, ByVal Description As String)` | a `Connect` with events failed (refused, unreachable) |
| `DataArrival(ByVal Bytes As Long)` | data arrived; Bytes is how much is waiting now. Read it with `Receive`, `ReceiveLine` (when `Peek` shows a whole line) or `ReceiveFrom` (UDP). It fires once per arrival: data you leave unread doesn't fire it again, but more data does. |
| `Close()` | the other side closed the connection (data may still be waiting: read it) |
| `ConnectionRequest()` | a client is connecting to a listening socket: call `Accept` here. A request that isn't accepted is refused. |
| `ClientDataArrival(ByVal Client As Socket, ByVal Bytes As Long)` | on a listening socket: data arrived on one of the connections it accepted |
| `ClientClose(ByVal Client As Socket)` | on a listening socket: one of its connections was closed by the other side |

The `Client...` events let one handler serve every connection of a server: an accepted socket
without event handlers of its own reports to its listening socket. Keep the accepted sockets
somewhere (a Collection), since a socket nobody refers to is closed.

```basic
' chat server: everything one client sends goes to all of them
Dim WithEvents server As Socket
Dim clients As New Collection

Sub Main()
    Set server = CreateObject("Socket")
    server.Listen 7000
    Do: server.WaitEvents 1000: Loop     ' a form program needs no loop of its own
End Sub

Sub server_ConnectionRequest()
    clients.Add server.Accept()
End Sub

Sub server_ClientDataArrival(ByVal Client As Socket, ByVal Bytes As Long)
    Dim line As String, c As Variant
    Do While InStr(Client.Peek(), vbLf) > 0
        line = Client.ReceiveLine()
        For Each c In clients
            If c.Connected Then c.SendLine Client.RemoteHost & ": " & line
        Next
    Loop
End Sub

Sub server_ClientClose(ByVal Client As Socket)
    Dim i As Long
    For i = clients.Count To 1 Step -1
        If clients(i) Is Client Then clients.Remove i
    Next
    Client.Close
End Sub
```

**Where events fire.** In a form program, in the event loop (between other events), with no code
needed. In a program without forms, in `DoEvents` and in `s.WaitEvents([ms])`, which waits up
to ms milliseconds (default `Timeout`) for events of any socket, fires them and returns True if
any fired. Events never interrupt running code. A handler's run-time error ends the program, as
in any event handler.

## Errors

The waiting calls raise run-time errors, catchable with `On Error` (the same numbers as `Http`):

| `Err.Number` | |
|---|---|
| 31102 | the host name can't be resolved |
| 31103 | can't connect (refused, unreachable, no TCP/IP stack), can't listen or bind (port in use) |
| 31104 | nothing within `Timeout` (Connect, Send, Read, ReceiveLine) |
| 31109 | the socket isn't open, or the connection broke while sending |
| 380 | a port outside 0-65535, or a negative Timeout |
| 5 | a call that doesn't fit the socket (Send on a UDP socket, Accept on one that isn't listening) |
| 18 | interrupted with Ctrl-C |

## How it works, per platform

**AmigaOS 4.** `bsdsocket.library` (Roadshow), opened on first use, so a program that never
makes a socket doesn't need a running TCP/IP stack. All sockets are non-blocking; the waiting
calls use `WaitSelect` with Ctrl-C, so they can be interrupted. A form program with sockets waits
in `WaitSelect` for the sockets and the window, timer and ARexx signals together, so it uses no
CPU while idle. Host names are resolved with `gethostbyname`, which has no timeout: with no
reachable DNS server an unknown name can take minutes, so prefer addresses on such setups.
IPv4 only. Some Roadshow setups have no loopback interface, so `127.0.0.1` can't be used
there; `MachineAddress` gives the address to use for talking to yourself.

**Host (macOS, Linux).** BSD sockets with `poll`; IPv4.

## Tests

- `tests/socket/tcpudp.bas` (part of `make test`, VM, JIT and native): a server and clients in one
  program over 127.0.0.1 (or `MachineAddress` where there is no loopback): waiting calls, lines,
  a 200 KB transfer, binary data, timeouts, refused connections, events (Connect,
  ConnectionRequest, DataArrival, Close, Error, ClientDataArrival, ClientClose) and UDP.
- `tests-net/sockform` (`tests-net/socket-run.sh`, part of `make test`): socket events in a form
  program interleaved with a Timer (headless forms, VM and native); `tests-net/sockresolve.bas`
  an unknown host name (host only).
- On the AmigaOS 4 guest: `tools/os4-libtest.py tests/socket/tcpudp.bas both`.
- Example: `examples/chat`, a chat room form program (host or join).

## Not yet

TLS sockets (use `Http` for HTTPS), IPv6, a `Send` that doesn't wait (large sends from a form
wait until the data is out), resolving host names without waiting.
