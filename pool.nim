# prototype
{.experimental.}

import asyncdispatch
import asyncnet
import msgpack
import msgpack_rpc
import locks

type AllocFn* = proc (): AsyncSocket

type Pool = ref object
  lock: TLock
  free: seq[AsyncSocket]
  used: seq[AsyncSocket]
  allocFn: AllocFn

proc mkPool(f: AllocFn): Pool =
  result = Pool(
    free: newSeq[AsyncSocket](),
    used: newSeq[AsyncSocket](),
    allocFn: f
  )
  initLock(result.lock)

proc destroy(pool: Pool) {.override.} =
  assert(len(pool.used) == 0)
  deinitLock(pool.lock)
  for sock in pool.free:
    sock.close()
  
proc size(pool: var Pool): int =
  pool.lock.acquire
  result = len(pool.free) + len(pool.used)
  pool.lock.release

proc acquire(pool: var Pool): AsyncSocket =
  pool.lock.acquire
  if len(pool.free) == 0:
    pool.free.add(pool.allocFn())
  assert(len(pool.free) > 0)
  let i = high(pool.free)
  result = pool.free[i]
  pool.free.delete(i)
  pool.used.add(result)
  pool.lock.release
 
proc release(pool: var Pool, sock: AsyncSocket) =
  pool.lock.acquire
  let i = pool.used.find(sock)
  pool.used.delete(i)
  pool.free.add(sock)
  pool.lock.release

type MultiFuture* = ref object
  futs: seq[Future[Msg]]
  finFuts: seq[Msg]
  pool: Pool

proc mkMultiFuture*(f: AllocFn): MultiFuture =
  result = MultiFuture (
    futs: newSeq[Future[Msg]](),
    finFuts: newSeq[Msg](),
    pool: mkPool(f)
  )

proc add*(mfut: MultiFuture, name: string, args: seq[Msg]) =
  var mfut = mfut # without this, "illegal capture" error
  let sock = mfut.pool.acquire()
  let cli = mkClient(sock)
  var fut = cli.call(sock.getFd().int, name, args)
  fut.callback = proc () =
    mfut.pool.release(sock)
    mfut.finFuts.add(fut.read)
  mfut.futs.add(fut)

iterator eachResult*(mfut: MultiFuture): Msg =
  var i = 0
  while (len(mfut.finFuts) > i and i < len(mfut.futs)):
    yield mfut.finFuts[i]
    i += 1

proc join*(mfut: MultiFuture): seq[Msg] =
  for fut in mfut.futs:
    discard waitFor(fut)
  mfut.finFuts
