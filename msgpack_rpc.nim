{.experimental.}

#
# MessagePack-RPC
#

import msgpack
import asyncdispatch
import asyncnet
import rawsockets
import streams
import tables

let READFULL = 1 shl 63 # as large as to read full data sequence

# openArray?
type RPCMethod* = proc (args: openArray[Msg]): Msg
## TODO desc

type Server* = object
  sock: AsyncSocket
  methods: TableRef[string, RPCMethod]

proc mkServer*(sock: AsyncSocket): Server =
  Server(
    sock: sock,
    methods: newTable[string, RPCMethod]()
  )

proc addMethod*(server: var Server, name: string, f: RPCMethod) =
  # check (echo and return bool?)
  server.methods.add(name, f)

proc decompose(data: string): seq[Msg] =
  let st = newStringStream(data)
  let msg = st.unpack
  msg.unwrapArray

proc handleRequest(server: Server, conn: AsyncSocket): Future[void] {.async.} =
  proc noMethod(server: Server, name: string) =
    if not server.methods.hasKey(name):
      raise newException(KeyError, "no method found")

  let inData = await conn.recv(READFULL)
  let inMsg: seq[Msg] = decompose(inData)
  let typ = unwrapInt(inMsg[0])
  case typ:
  of 0: # request: [0, id, method, params]
    # let id = unwrapInt(inMsg[1])
    let name = unwrapStr(inMsg[2])

    # respose: [1, id, error, retval]
    let outMsg: Msg = try:
      noMethod(server, name)
      let f: RPCMethod = server.methods[name]
      let ret = f(unwrapArray(inMsg[3]))
      FixArray(@[PFixNum(1), inMsg[1], Nil, ret])
    except Exception:
      FixArray(@[PFixNum(1), inMsg[1], (-1).toMsg, Nil])

    var st = newStringStream()
    st.pack(outMsg)
    await conn.send(st.data)
  of 2: # notify: [2, method, params]
    let name = unwrapStr(inMsg[1])
    try:
      noMethod(server, name)
      let f = server.methods[name]
      discard f(unwrapArray(inMsg[2]))
    except Exception:
      discard
  else:
    echo "bad request (request type isn't either 0 or 2) received"
    discard

proc run*(server: Server) {.async.} =
  proc loop(server: Server): Future[void] {.async.} =
    while true:
      let conn = await server.sock.accept
      asyncCheck server.handleRequest(conn)
  await server.loop() # () required otherwise compile fails

type Client = object
  sock: AsyncSocket

proc mkClient*(sock: AsyncSocket): Client =
  Client(sock: sock)

# TODO varargs (illegal capture?)
proc call*(cli: Client, id: int, name: string, args: seq[Msg]): Future[Msg] {.async.} =
  let reqMsg: Msg = FixArray(@[PFixNum(0), wrap(id), wrap(name), wrap(args)])
  var st = newStringStream()
  st.pack(reqMsg)
  # st.setPosition(0)
  await cli.sock.send(st.data)
  let ackData = await cli.sock.recv(READFULL)
  # Response: [1, id, error, retval]
  let ackMsg = decompose(ackData)
  let typ = unwrapInt(ackMsg[0])
  result =
    case typ:
    of 1:
      let id = unwrapInt(ackMsg[1])
      if ackMsg[2].kind == mkNil:
        ackMsg[3]
      else:
        ackMsg[2]
    else:
      echo "server replies with bad response type ", typ
      assert(false)
      Nil

proc notify(cli: Client, fun: Msg, args: openArray[Msg]): Future[void] {.async.} =
  discard
