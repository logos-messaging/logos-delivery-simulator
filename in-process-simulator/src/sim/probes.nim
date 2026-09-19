## Run-validity instrumentation.
##
## The simulator runs every node on one chronos dispatcher, so once the
## dispatcher saturates, measured "propagation latency" is really queueing delay.
## The lag probe measures that directly: it is what decides whether a run's
## latency numbers mean anything, or whether the run reports coverage/bandwidth
## only.

{.push raises: [].}

import std/[algorithm, math]
import chronos

type LagProbe* = ref object
  samples*: seq[float]   ## observed oversleep, milliseconds
  interval: Duration
  running: bool

proc newLagProbe*(interval = chronos.milliseconds(10)): LagProbe =
  LagProbe(samples: newSeqOfCap[float](8192), interval: interval)

proc loop(p: LagProbe) {.async: (raises: []).} =
  while p.running:
    let t0 = Moment.now()
    try:
      await sleepAsync(p.interval)
    except CancelledError:
      return
    let slept = Moment.now() - t0
    p.samples.add((slept - p.interval).nanoseconds.float / 1_000_000.0)

proc start*(p: LagProbe) =
  p.running = true
  asyncSpawn p.loop()

proc stop*(p: LagProbe) =
  p.running = false

proc percentile*(xs: seq[float], q: float): float =
  if xs.len == 0: return 0.0
  var s = xs
  s.sort()
  let idx = clamp(int(floor(q * float(s.len - 1)) + 0.5), 0, s.len - 1)
  s[idx]
