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

# BUG!! don't use this. too big?
# let READFULL = 1 shl 63 # as large as to read full data sequence
let READFULL = 1000

# openArray?
type RPCMethod* = proc (args: openArray[Msg]): Msg
## TODO desc

type Server* = object
  sock: AsyncSocket
  methods: TableRef[string, RPCMethod]

proc newServer*(sock: AsyncSocket): Server =
  Server(
    sock: sock,
    methods: newTable[string, RPCMethod]()
  )

proc addMethod*(server: var Server, name: string, f: RPCMethod) =
  # check (echo and return bool?)
  server.methods.add(name, f)

proc decompose(data: string): seq[Msg] =
  echo "len: ", len(data)
  let st = newStringStream(data)
  let msg = st.unpack
  msg.unwrapArray

proc handleRequest(server: Server, conn: AsyncSocket): Future[void] {.async.} =
  proc noMethod(server: Server, name: string) =
    if not server.methods.hasKey(name):
      raise newException(KeyError, "no method found")

  let inData: string = await conn.recv(READFULL)
  echo "decomp server"
  let inMsg: seq[Msg] = decompose(inData)
  let typ = unwrapInt(inMsg[0])
  case typ:
  of 0: # request: [0, id, method, params]
    let id = unwrapInt(inMsg[1])
    let name = unwrapStr(inMsg[2])
    echo "id ", id

    # respose: [1, id, error, retval]
    let outMsg: Msg = try:
      noMethod(server, name)
      let f: RPCMethod = server.methods[name]
      let ret = f(unwrapArray(inMsg[3]))
      FixArray(@[PFixNum(1), inMsg[1], Nil, ret])
    except Exception:
      echo "error"
      FixArray(@[PFixNum(1), inMsg[1], (-1).toMsg, Nil])

    echo "ack start ", id
    echo outMsg
    var st = newStringStream()
    st.pack(outMsg)
    # st.setPosition(0)
    await conn.send(st.data)
    echo "ack end ", id
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
      echo "loop"
      let conn = await server.sock.accept
      echo "start to handle conn"
      # shouldn't be await which really waits for return before proceed to next loop
      asyncCheck server.handleRequest(conn)
  await server.loop() # () required otherwise compile fails

type Client = object
  sock: AsyncSocket

proc newClient*(sock: AsyncSocket): Client =
  Client(sock: sock)

# TODO varargs (illegal capture?)
proc call*(cli: Client, id: int, name: string, args: seq[Msg]): Future[Msg] {.async.} =
  echo "call start"
  let reqMsg: Msg = FixArray(@[PFixNum(0), wrap(id), wrap(name), wrap(args)])
  echo reqMsg
  var st = newStringStream()
  st.pack(reqMsg)
  # st.setPosition(0)
  echo "cli: send start"
  echo len(st.data)
  let fut = cli.sock.send(st.data) # return to caller
  echo "cli: send end"
  await fut
  echo fut.finished
  echo fut.failed
  let ackData = await cli.sock.recv(READFULL)
  echo "cli: recv end"
  # Response: [1, id, error, retval]
  echo "decomp cli"
  let ackMsg = decompose(ackData)
  let typ = unwrapInt(ackMsg[0])
  result =
    case typ:
    of 1:
      let id = unwrapInt(ackMsg[1])
      if ackMsg[2].kind == mkNil:
        ackMsg[3]
      else:
        ackMsg[2] # FIXME don't return different type. (ok, val) pattern?
    else:
      echo "server replies with bad response type ", typ
      assert(false)
      Nil
  echo "call end"

proc notify(cli: Client, fun: Msg, args: openArray[Msg]): Future[void] {.async.} =
  discard

# ------------------------------------------------------------------------------

import locks

{.passL: "-lpthread".}

type SocketAllocFn* = proc (): AsyncSocket

type SocketPool* = ref object
  lock: TLock
  allocFn: SocketAllocFn
  free: seq[AsyncSocket]
  used: seq[AsyncSocket]

proc newSocketPool*(f: SocketAllocFn): SocketPool =
  result = SocketPool(
    free: newSeq[AsyncSocket](),
    used: newSeq[AsyncSocket](),
    allocFn: f,
  )
  initLock(result.lock)

proc destroy(pool: SocketPool) {.override.} =
  echo "destroy pool"
  assert(len(pool.used) == 0)
  deinitLock(pool.lock)
  for sock in pool.free:
    sock.close()
  
proc size*(pool: var SocketPool): int =
  # pool.lock.acquire
  result = len(pool.free) + len(pool.used)
  # pool.lock.release

proc acquire(pool: var SocketPool): AsyncSocket =
  # pool.lock.acquire
  if len(pool.free) == 0:
    pool.free.add(pool.allocFn())
  assert(len(pool.free) > 0)
  let i = high(pool.free)
  result = pool.free[i]
  pool.free.delete(i)
  pool.used.add(result)
  # pool.lock.release
 
proc release(pool: var SocketPool, sock: AsyncSocket) =
  # pool.lock.acquire
  let i = pool.used.find(sock)
  pool.used.delete(i)
  pool.free.add(sock)
  # pool.lock.release

type MultiFuture* = ref object
  lock: TLock
  futs: seq[Future[Msg]]
  finFuts: seq[Msg]
  pool: SocketPool

proc join*(mfut: MultiFuture): seq[Msg] =
  echo "join"
  ## Wait for all requests and the results in-order.
  var s = newSeq[Msg](len(mfut.futs))
  for i, fut in mfut.futs:
    assert(fut != nil)
    let e: Msg = waitFor(fut)
    s[i] = e
  s

proc newMultiFuture*(pool: SocketPool): MultiFuture =
  result = MultiFuture (
    futs: newSeq[Future[Msg]](),
    finFuts: newSeq[Msg](),
    pool: pool,
  )
  initLock(result.lock)

proc destroy(mfut: MultiFuture) {.override.} =
  echo "destroy multifuture"
  discard mfut.join
  deinitLock(mfut.lock)

proc add*(mfut: MultiFuture, name: string, args: seq[Msg]) =
  ## Add a new future
  let sock = mfut.pool.acquire()
  let cli = newClient(sock)
  let fut = cli.call(sock.getFd().int, name, args)
  fut.callback = proc () =
    echo "callback"
    mfut.lock.acquire
    mfut.finFuts.add(fut.read)
    mfut.lock.release
    mfut.pool.release(sock)
  assert(fut != nil)
  mfut.futs.add(fut)
  assert(len(mfut.futs) > 0)

iterator eachResult*(mfut: MultiFuture): Msg =
  ## Make an iterator that generates result in order of completion.
  var i = 0
  while (len(mfut.finFuts) > i and i < len(mfut.futs)): # FIXME use waitqueue
    yield mfut.finFuts[i]
    i += 1
