# nREPL Protocol Specification

The nREPL protocol is designed to solve the ["narrow waist"
problem][1] where you have N languages and M editors, and you want to
avoid having to create NxM adapters across them. In this way it shares
a lot with the [Language Server Protocol][2], though it predates LSP
by several years. However, the focus is different; LSP achieves its
integration using static analysis, while nREPL achieves it by running
project code. Writing an nREPL server is much easier than writing an
LSP server and can be done in a couple hundred lines.

The nREPL protocol has its roots in the Clojure community; at the time
of this writing most nREPL users are Clojure users. But the design of
the protocol is language-agnostic and can be applied to any language
that can evaluate code at runtime.

This document is an in-progress draft describing version 0.1.0 of the
nREPL protocol.

## Protocol Description

The nREPL protocol operates by default by exchanging [bencoded][3]
messages over a socket. Various implementations may also offer other
encodings and transports, such as JSON over stdio, but these are not
standardized.

While it's somewhat unusual, bencode was chosen because it is a good
deal easier to implement than JSON; usually it can be done in under a
hundred lines of code. Unfortunately bencode is not particularly
readable, so examples in this document will show messages in JSON.

Every message sent by the client must have an `op` field, for
operation.  Every message except the first `clone` request must have a
`session` field indicating which session it's part of.

Every message sent by the client is a request. Requests can have one
or more response messages associated with them. Because a request can
have many responses, every request should be considered active until a
response is received with a `status` field which is a list that
contains the string `done`. Requests may remain active for a long time
before completing, so the responses should be handled asynchronously.

Requests should have an `id` field, and responses to that request
should also include the same `id`. Depending on the concurrency
features of the language, it may be possible for multiple requests to
overlap.

In this document, the examples use UUID strings for `session` and
`id`, but the only requirement is that they are strings that are
unique to the life of the specific server process and all clients
connecting to it.

When an error is encountered in the nREPL server itself (rather than
in the code that the client has sent) it should send a response with
`err` containing a message describing the error, and a `status`
containing `server-error` as well as `done`.

## Required Operations

The absolute minimum a server needs to support are the first four ops,
`clone`, `eval`, `stdin`, and `describe`. Clients may support
`describe` but this is not required.

### `clone` op

Messages are exchanged in sessions. In order to start a session, the
client sends a message with the `clone` op:

```json
// client -> server
{"op": "clone",
 "id": "01e0bbed-2819-41b8-9642-4c16a79f7efc",
 "client-name": "nREPL documentation demo",
 "client-version" "1.0.0"}
```

All fields except `op` are optional. Client information may be used
for debugging purposes.

The response will contain a new `new-session` id which should be
included as the `session` for all subsequent requests:

```json
// client <- server
{"new-session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "01e0bbed-2819-41b8-9642-4c16a79f7efc",
 "status": ["done"]}
```

The server should support multiple sessions on a single socket.

[why is this an explicit op? why not just automatically register a
session any time a request comes in without a session attached?]

### `eval` op

This is the main workhorse operation where code gets run. The `code`
field contains the code to be run.

```json
// client -> server
{"op": "eval",
 "session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "297a1dc1-e8ea-4a71-ac58-977841a301f4",
 "code": "99 + 121"}
```

This should normally return a message with a `value` field containing
a string representation of the return value.

```json
// client <- server
{"session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "297a1dc1-e8ea-4a71-ac58-977841a301f4",
 "value": "220",
 "status": ["done"]}
```

In the case that evaluated code produces output, the server should
send messages that have `out` or `err` fields, for stdout and stderr
respectively. These may be sent in a separate message sent before the
"done" message that has `value` in it, or they may be present in that
message. The client should display these to the user in a way that
makes it clear they are part of the session; for example, in the editor
console right below the code was entered.

```json
// client -> server
{"op": "eval",
 "session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "35e53d19-9f4a-4329-a820-d71481fdfec1",
 "code": "print('hello, world')"}

// client <- server
{"session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "35e53d19-9f4a-4329-a820-d71481fdfec1",
 "value": "nil",
 "out": "hello world",
 "status": ["done"]}
```

In the case that evaluated code encounters an error, the response
message should include an `ex` field instead of `value`. The format of
this field will vary depending on the way the language in question
represents errors.

[should we go into detail about how to send stack traces?]

```json
// client -> server
{"op": "eval",
 "session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "b9616f31-9fbd-4a76-b7d6-ab98eb9f7641",
 "code": "client.connect(config.hostname, config.port)"}

// client <- server
{"session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "b9616f31-9fbd-4a76-b7d6-ab98eb9f7641",
 "ex": "connection refused",
 "status": ["done"]}
```

The `eval` message may also contain a `file` field indicating that the
code in question should be treated as if it came from a given file. If
this is not an absolute path, it should be interpreted as being
relative to the directory from which the server was started. The
`line` and `column` fields may include numbers indicating where in the
file the code was from. Lines start at 1 and columns start at 0. These
fields typically do not affect how the code is run, but they may help
improve stack traces if there is an error.

In some languages, evaluation always happens in the context of a
specific namespace or module. For those languages, an `ns` field can
be included in the request which indicates the namespace to evaluate
the code in.

```json
// client -> server
{"op": "eval",
 "session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "2102c017-2ff5-4ddd-9067-a54ec62fc0c8",
 "file": "src/display/avatar.lua",
 "line": 21,
 "column": 8,
 "ns": "display.avatar",
 "code": "avatar.reload()"}
```

### `stdin` op

In the case that evaluated code tries to read input from standard in,
the server will send a message to the client with a status of
`need-input`. When this happens, the client should accept input and
send what it receives using the `stdin` operation.

```json
// client -> server
{"op": "eval",
 "session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "78f78353-c185-4211-a868-b19eaa85e054",
 "code": "subsystem.activate()"}

// client <- server
{"session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "78f78353-c185-4211-a868-b19eaa85e054",
 "out": "Username: ",
 "status": ["need-input"]}

// client -> server
{"op": "stdin",
 "session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "78f78353-c185-4211-a868-b19eaa85e054",
 "stdin": "gorkon"}

// client <- server
{"session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "78f78353-c185-4211-a868-b19eaa85e054",
 "output": "Activated.\n",
 "value": "nil",
 "status": ["done"]}

```

### `describe` op

If a client wishes to know which operations are supported by a server,
it can query with the `describe` op, which takes no other parameters:

```json
// client -> server
{"op": "describe",
 "session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "5d90576e-b5e1-4499-a43d-c75c60b579ff"}
```

The response must have a list of `ops` supported by the server. It may
also have a dictionary of `versions` for debugging purposes as well as
a dictionary of `features` describing additional extensions beyond the
nREPL specification.

```json
// client <- server
{"session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "5d90576e-b5e1-4499-a43d-c75c60b579ff",
 "ops": ["clone", "eval", "stdin", "describe", "load-file", "sandbox"],
 "features": {"encodings": ["bencode", "json"],
              "transports": ["socket", "stdio"]},
 "versions": {"nrepl": "0.1.0",
              "lua": "5.4"},
 "status": ["done"]}
```

Compatibility note: previous versions of the protocol had `ops`
defined as a dictionary with the operation names as the keys and an
unspecified dictionary as the values. This is no longer recommended.

## Optional operations

Servers may choose to support these if they make sense. If a server
receives a request with an `op` it does not recognize, it must reply
with a message whose `status` contains `unknown-op` along with `done`.

### `interrupt` op

For servers that support interrupting running code, the client may
send an `interrupt` op. Requests may optionally contain an
`interrupt-id` field which corresponds to the `id` of the request to
be interrupted. If this is omitted, it interrupts the most recent
request of the current session.

```json
// client -> server
{"op": "eval",
 "session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "71629c7e-6c73-4dea-85f8-102d4b64c07f",
 "code": "calculate_matrix()"}

// client -> server
{"op": "interrupt",
 "session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "71629c7e-6c73-4dea-85f8-102d4b64c07f""}
```

The reply to this request should be a message with statuses
`interrupted` and `done` both:

```json
// client <- server
{"session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "78f78353-c185-4211-a868-b19eaa85e054",
 "status": ["interrupted" "done"]}
```

### `lookup` op

For servers that support providing documentation and reflective
information for functions and other values, the client may send a
`lookup` op containing a `sym` field for the item being looked up.

```json
// client -> server
{"op": "lookup",
 "session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "d30f8bb9-4e6e-48a8-b0f8-58adf5b353a7",
 "sym": "mymodule.reloader"}
```

The response will vary from one server to another due to language
variation, but all data should be under `info`. If documentation is
available, it should be under `doc`, and argument lists for functions
should be under `arglist`.

If the definition of the requested value can be traced to a file, then
a `file` and `line` field should be included. A `column` may also be
provided. Line numbers are counted from 1, and column numbers are
counted from 0. If it was found inside an archive, for example a zip
file or a jar file, it should also include an `archive` field
containing a path to the archive file. If `archive` is present, then
`file` is interpreted as being inside the archive; otherwise it is
either an absolute path or interpreted as being relative to the
directory in which the server was started.

```json
// client <- server
{"session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "78f78353-c185-4211-a868-b19eaa85e054",
 "info": {"doc": "Reloads the configuration.",
          "arglist": ["path", "restart"],
          "file": "src/mymodule.lua",
          "line": 27,
          "column": 2,
          "archive": "lib/extras.zip"},
 "status": ["done"]}
```

If the `sym` is not found, then the `info` field should be omitted.

### `load-file` op

A client may instruct the server to load an entire file instead of
sending its contents across the session. It may send a request with a
`load-file` op which has `file-path` indicating the path to the file
to load. Depending on the server, in some cases this may result in the
loaded code having better stack trace information.

If `file-path` is not an absolute path, it should be interpreted as
being relative to the directory from which the server was started.

```json
// client -> server
{"op": "load-file",
 "session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "b5c90973-bf4f-4626-a825-e493eed4759a",
 "file-path": "src/utils.lua"}
```

The response should be interpreted similarly to the `eval` op: a
`value` or `err` may be included, but omitting both is also allowed.
It may also include `out` and/or `err`.

```json
// client <- server
{"session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "b5c90973-bf4f-4626-a825-e493eed4759a",
 "value": "{debug=#<function: 0x5618eb88b180>}",
 "status": ["done"]}
```

Compatibility note: older versions of nREPL required a `file` field
which contained code that was simply evaluated. This behavior is no
longer recommended.

### `completions` op

A client may request completions for a given input using the
`completions` op. The `prefix` field should be a string indicating the
input to be completed. For servers where completions may be specific
to a module or namespace context, an `ns` field may also be included
indicating this.

```json
// client -> server
{"op": "completions",
 "session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "d862f516-a232-4e01-a4c1-1afb42e04637",
 "prefix": "math.s"}
```

The response should contain a `completions` field with a list of
completion candidates: dictionaries with fields `candidate` with the
full text to complete, and `type` describing the candidate's type.

```json
// client <- server
{"session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "d862f516-a232-4e01-a4c1-1afb42e04637",
 "completions": [{"candidate": "math.sqrt", "type": "function"},
                 {"candidate": "math.sin", "type": "function"},
                 {"candidate": "math.sinh", "type": "function"}],
 "status": ["done"]}
```

### `close` op

A client may send a `close` op to terminate the session.

```json
// client -> server
{"op": "close",
 "session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "5da7c522-24eb-4a77-a133-63f08c4bdc1e"}

// client <- server
{"session": "afd3c88e-707f-4169-a265-892f29476333",
 "id": "5da7c522-24eb-4a77-a133-63f08c4bdc1e",
 "status": ["done"]}
```

The server may close the socket after the reply is sent, if the
session is connected over a socket and the socket is not being used
for other sessions. The client may close the socket to achieve the
same effect. 

If the server was communicating over stdio, it may exit if no other
sessions are active, but if it was communicating over a socket, it
should remain running to accept sessions from other clients.

## Extension operations

Each server may include support for additional ops that are not part
of the protocol. Support for these ops should be indicated by
including them in the `ops` from the `describe` op, so clients can
discover them dynamically.

If your client wants to perform some operation that is not part of the
spec and it only needs to support a single language, it can send the
implementation of this operation across the wire using `eval`, and
indeed, many clients have done this. For example, earlier versions of
the nREPL protocol did not have a `completions` operation, and so some
clients sent Clojure code to calculate completions and parsed the
`value` reply to determine what to display to the user. However, this
is not an ideal solution; it creates incompatibilities across
languages and puts server code in the client.

Rather than sending code across the wire for an op, you may propose a
draft extension to the nREPL protocol so that clients can standardize
on it instead. Future versions of this document may link to a list of
proposed extensions.

[1]: https://www.oilshell.org/blog/2022/02/diagrams.html
[2]: https://langserver.org
[3]: https://wiki.theory.org/index.php/BitTorrentSpecification#Bencoding
