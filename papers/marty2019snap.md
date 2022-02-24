# Snap: a Microkernel Approach to Host Networking

[Marty and De Kruijf, et al. 2019. Snap: a Microkernel Approach to Host
Networking. In ACM SIGOPS 27th Symposium on Operating Systems Principles (SOSP
’19), October 27–30, 2019, Huntsville, ON, Canada. ACM, New York, NY, USA, 15
pages. https://doi.org/
10.1145/3341301.3359657](https://dl.acm.org/doi/10.1145/3341301.3359657)

Host networking needs are evolving due to:

- continuous capacity growth seeking new approaches to edge switching &
  bandwidth management
- rise of cloud computing seeking rich virtualization features
- high-performance distributed systems seeking efficient & low latency comms

Reasons for moving network functions from kernel-space to user-space:

- developing kernel code is slow & only few engineers could do it
- feature release through kernel module reloads covered a subset of
  functionality & required disconnecting apps
- more common case required machine reboots which required draining the machine
  of running apps
- change of kernel-based stack took 1-2 months to deploy, whereas a new Snap
  release done on a weekly basis
- broad generality of Linux made optimization difficult & defied vertical
  integration efforts, which were easily broken by upstream changes

This paper presents a microkernel-inspired approach to host networking called
Snap. Snap is a userspace networking system with flexible modules that implement
various networking functions, including:

- edge packet switching
- virtualization for cloud platforms
- traffic shaping policy enforcement
- high-performance reliable messaging
- RDMA-like service

Systems design principles for Snap:

- Snap implements host networking functions as an ordinary Linux userspace
  process (microkernel-inspired approach)
    - Retains centralized resource allocation & management benefits of
      monolithic kernel
    - High rate of feature development with transparent software upgrades
    - Improves accounting & isolation by accurately attributing both CPU &
      memory consumed on behalf of apps to those apps using Linux kernel
      interfaces to charge CPU & memory to app constainers
    - Leverages user-space security tools like memory access sanitizers, fuzz
      testers
- Interoperable with existing kernel network functions & app thread schedulers
  - Implements custom kernel packet injection driver for packet processing
    through both Snap & Linux kernel networking stack
  - Implements custom CPU scheduler without adopting new runtimes
- Encapsulates packet processing functions (data plane ops) into composable
  units called "engines"
  - stateful, single-threaded tasks scheduled & run by a Snap engine scheduling
    runtime using lock-free communication over memory-mapped regions shared with
    the input or output
  - enables modular CPU scheduling
    - engines are organized into groups sharing a common scheduling discipline
  - incremental & minimally-disruptive state transfer during upgrades
  - examples: packet processing for network virtualization, pacing, rate
    limiting, stateful network transport like "Pony Express"
- Provides support for OSI L4 & L5 functions through Pony Express transport
  - A Pony Express engine services incoming packets, interacts with apps, runs
    state machines to advance messaging & one-sided ops, and generate outgoing
    packets
  - Interface similar to RDMA capable "smart" NIC
  - Transparently leverages stateless h/w offload capabilities in emerging NICs
      - includes Intel I/OAT DMA device to offload memory copy ops
      - another example: end-to-end invariant CRC32 calculation over each packet
  - Given zero-copy capability, NIC NUMA node locality & locality within the
    transport layer are together more important than locality with the app
    thread, & hence Pony Express runs transport processing in a thread separate
    from the app, and instead shares CPU with other engines & other transport
    processing
  - Ability to rapidly deploy new versions of Pony Express significantly aided
    development & tuning of congestion control
  - Ability to easily update & change wire protocols
  - Just-in-time generation of packets based on availability of NIC transmit
    descriptor slots ensures no per-packet queueing in the engine
  - One-sided ops don't involve app code on the remote destination &
    executes-to-completion within Pony Express engine
      - Supports rich operations such as "indirect read" to determine actual
        memory target to access from local app-filled indirection tables, and
        "scan & read" - naive RDMA benefits disappear in these cases
  - Provides mechanism to create message streams to avoid HoL blocking
  - Flow control is mix of receiver-driven buffer posting as well as a shared
    buffer pool managed using credits
      - Flow control for one-sided ops rely on congestion control & CPU
        scheduling mechanisms rather than higher-level mechanisms
- Highly tuned Snap & Pony Express transport for performance to minimize I/O
  overhead
  - 3x better transport processing efficiency than baseline Linux
  - Supporting RDMA-like functionality at 5M IOPS/core
- Transparent upgrades
  - Gives ability to release new Snap versions without disrupting running apps
  - During upgrades, running version serializes all state to an intermediate
    format stored in memory shared with new versions, migrating engines one at a
    time, each in its entirety
  - Two-phase migration technique: brownout phase to perform preparatory
    background transfer & blackout phase when network stack is unavailable
  - Targetted blackout period is 200 ms or less
- Customizable emphasis between scheduling latency, performance isolation & CPU
  efficiency of engines. Snap supports three broad categories of scheduling
  modes for engine groups:
  - Dedicating cores
    - engines are pinned to dedicated hyperthreads on which no other work can
      run
    - doesn't allow CPU utilization to scale in proportion to load
    - minimizes latency via spin polling
    - static provisioning can strain system under load or overprovision
  - Spreading engines
    - scales CPU consumption in proportion to load to minimize scheduling tail
      latency
    - binds each engine to a unique thread that schedules when active & blocks
      on interrupt notification (triggered from either NIC or app) when idle
    - not subject to scheduling delays caused by multiplexing multiple engines
      onto a small number of cores
    - leverages MicroQuanta, an internal real-time kernel scheduling class,
      engines bypass default Linux CFS kernel scheduler & can quickly be
      scheduled to an available core upon interrupt delivery
        - a MicroQuanta thread runs for a configurable *runtime* out of every
          *period* time units, with remaining CPU time available to other
          CFS-scheduled tasks
    - interrupts have system-level interference effects like being scheduled to
      a core in a low-power sleep state or in midst of running non-preemptible
      kernel code
  - Compacting engines
    - collapses work onto as few cores as possible combining scaling advantages
      of interrupt-driven executing with cache-efficiency of dedicating cores
    - but relies on periodic polling of engine queueing delays to detect load
      imbalance instead of instantaneous interrupt signals
    - latency delay from polling engines plus the delay for statistical
      confidence in queueing estimation plus the delay in handing off engine to
      another core can be higher than latency of interrupt signaling

The paper shows the following results:

- Performance measurement between a pair of machines connected to same ToR
  switch, machines with Intel Skylake processor & 100Gbps NICs
- Baseline, single-stream throughput of TCP is 22Gbps with 1.2 cores/s
  utilization, & Snap/Pony delivers 38Gbps using 1.05 cores/s
- With 5000B MTU, Snap/Pony single-core throughput increases to over 67Gbps, &
  enabling I/OAT receive copy offload (with zero-copy tx) increases to over
  80Gbps
- Average RTT latency with TCP is 23 microsecs, & Snap/Pony delivers 18
  microsecs. Configuration with spin-poll reduces Snap/Pony's RTT latency to
  less than 10 microsecs and busy-polling sockets in Linux reduces latency to 18
  microsecs
- Both Snap engine schedulers ("spreading engines" and "compacting engines")
  succeed in scaling CPU consumption in proportion to load & shows sub-linear
  increase in CPU consumption due to batching efficiencies. Snap is 3x more
  efficient than TCP at high offered loads due to:
    - copy reduction
    - avoiding fine-grained synchronization
    - 5000B vs 4096B MTU difference between Snap/Pony & TCP
    - hotter instruction & data caches in case of the compacting scheduler
- While Snap compacting scheduler offers the best CPU efficiency, the spreading
  scheduler has the best tail latency
- Spreading scheduler relies on interrupts to wake on idleness, which is prone
  to system-level latency contributors - in these cases compacting engines
  provide best latency
    - NIC generated interrupt might target a core in deep power-saving C-state
    - Production machines run complex antagonists that can affect schedulability
      of even a MicroQuanta thread
- Conventional RPC stacks written on standard TCP sockets (gRPC) see less than
  100,000 IOPS/core, but Snap/Pony can provide up to 5M IOPS/core with custom
  batched indirect read ops
- Transparent upgrades with median blackout of 250ms

## Strengths

- This paper presents the design & architecture of Snap, a widely-deployed,
  microkernel-inspired system for host networking. They also describe a
  communication stack based on this microkernel approach & transparent upgrade
  abilities without draining apps from running machines. Snap has been running
  in production for 3 years (at the time of the paper) supporting communication
  needs of several critical systems. This shows that the design principles that
  they followed were successful & battle-hardened for Google-scale needs. They
  had already experimented with various in-application transport designs & found
  the drawbacks exceed the strengths:
    - They prioritize fast release schedules of the network stack which required
      them to decouple it from apps & the kernel for the transparent upgrades.
    - Most of the in-app transports required a spin-polling transport thread
      with a provisioned core in every app to ameliorate scheduling
      unpredictabilities. But this is impractical because it is common to run
      dozens of apps on a single machine.
- They design three scheduling disciplines which can be customized depending on
  the engine & it's required emphasis between CPU efficiency & latency:
  dedicating cores, spreading engines & compacting engines. The abstraction of
  engine is helpful for both the purpose of scheduling (through engine groups)
  as well as for supporting transparent upgrades. This is a strength of the Snap
  design.

## Weaknesses

- Much of the Snap scheduling mechanism relies on their internally-developed
  kernel scheduling class called MicroQuanta which provides a flexible way to
  share cores between latency-sensitive Snap engine tasks & other tasks, and
  also an internally-developed driver for efficiently moving packets between
  Snap and the kernel. Without any access into such internal tooling, one can
  only speculate their functionality & take their word for it. This makes the
  knowledge accessible to the community at a very high-level without deep-level
  understanding.
- The paper doesn't go into the details of how they implement memory management
  with Snap which is a significant challenge with non-kernel networking.

## Future Work

- Memory Mapping & Management: Pony Express registers some app-shared memory
  with the NIC for zero-copy transmit but does so selectively and some apps take
  a copy from the app heap memory into bounce buffer memory shared & registerd
  with Snap and vice versa. This means extra copies which can be avoided.
  Designing a custom system call to translate & temporarily pin the memory which
  is cheaper than a memory copy can improve performance. In general, memory
  mapping & management with non-kernel networking is a significant challenge.
- Dynamic CPU Scaling: Kernel TCP networking usage is very bursty in practice -
  sometimes, consuming upwards of a dozen cores over short bursts. Maybe there
  is a way to combine the CPU efficiency benefits of compacting engines and the
  better tail latency benefits at high Snap loads of spreading engines to
  achieve the best of both worlds. Scheduler design for host networking hosts is
  a challenge.
- Rebalancing Across Engines: One can consider fine-grained rebalancing flows
  across engines using mechanisms such as work stealing.
- Stateful Offloads: Currently they leverage stateless offloads, and do not
  mention about stateful h/w offloads in emerging h/w NICs.

