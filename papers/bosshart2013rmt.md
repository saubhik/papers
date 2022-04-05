# Forwarding Metamorphosis: Fast Programmable Match-Action Processing in Hardware for SDN

Pat Bosshart, Glen Gibb, Hun-Seok Kim, George Varghese, Nick McKeown, Martin
Izzard, Fernando Mujica, and Mark Horowitz. 2013. Forwarding metamorphosis: fast
programmable match-action processing in hardware for SDN. In Proceedings of the
ACM SIGCOMM 2013 conference on SIGCOMM (SIGCOMM '13). Association for Computing
Machinery, New York, NY, USA, 99–110.
DOI:https://doi.org/10.1145/2486001.2486011

Routing & forwarding within the network remains a confusing mix of routing
protocols (e.g. BGP, ICMP, MPLS) and forwarding behaviors (e.g. routers,
bridges, firewalls). The control and forwarding planes are intertwined inside
closed, vertically integrated boxes. SDN took a key step in abstracting network
functions by separating the roles of the control & forwarding planes via an open
interface between them, e.g. OpenFlow. OpenFlow is based on the Match-Action
approach. We need to implement Match-Action at 1 Tb/s speeds in hardware
exploiting pipelining & parallelism while living in the constraints of on-chip
table memories - switching chips are O(100) times faster at switching than CPUs
& O(10) times faster than NPUs.

The simplest approach is Single Match Table (SMT) model where a controller tells
the switch to match any set of packet header fields against entries in a single
match table. It can be easily implemented in Ternary Content Addressable Memory
(TCAM). But this table needs to store every combination of headers, which is
wasteful.

Multiple Match Tables (MMT) is a refinement of SMT model. It allows multiple
smaller match tables to be matched by a subset of packet fields. These match
tables are arranged in a pipeline of stages.

## Problem 1: Inflexible Match-Action Processing

The OpenFlow spec transitioned to the MMT model but does not mandate the width,
depth, or number of tables. Existing switch chips fix the width, depth, or
number of tables during fabrication. This severely limits flexibility:

- a chip used in core router requires very large 32-bit IP prefix table & a
  small 128-bit ACL match table
- a chip used for L2 bridge requires 48-bit L2 DA (destination MAC address)
  match table & another 48-bit L2 SA (source MAC address) match table.
- entrerprise router requires much smaller 32-bit IP prefix table but a much
  larger ACL table and some MAC address match tables

This creates problems for network operators who want to tune the table sizes to
optimize for their network, or implement new forwarding behavior.

## Problem 2: Limited repertoire of packet processing actions

E.g. forwarding, dropping, decrementing TTLs, pushing VLAN or MPLS headers, &
GRE encapsulation. This action set is not extensible & not abstract enough to
allow any field to be modified, any state machine to be updated, and the packet
to be forwarded to an arbitrary set of output ports.

The paper explores Reconfigurable Match Tables, a refinement of the MMT model.

- Field definitions can be altered & new fields added.
- The number, topology, widths, depths of match tables can be specified, subject
  to overall resource limits on the number of matched bits.
- New actions may be defined, such as writing new congestion fields.
- Arbitrarily modified packets can be placed in specified queue(s), for output
  at any subset of parts, with a queueing discipline specified for each queue.

This work describes a RMT chip architecture to provide an existence proof of RMT
to standardize the reconfiguration interface between the controller and the data
plane. The work also provide use cases that show how the RMT model can be
configured to implement forwarding using Ethernet & IP headers, and support RCP.
The work describes an implementation of a 64x10Gb/s RMT switch chip to show that
a general form of the RMT model is feasible & inexpensive.

- The RMT architecture has a reconfigurable parser. The parser output is a
packet header vector, which is a set of header fields such as IP dest, Ethernet
dest, etc. The packet header vector includes metadata fields such as input port
on which the packet arrived, router state variables such as queue sizes.
- The PHV flows through a sequence of logical match stages. Each logical match
stage is a logical unit of packet processing, e.g. Ethernet or IP processing.
- Packet modifications are done using VLIW action that operate on all fields in
the PHV concurrently.
- A packet's fate is controlled by updating a set of dest ports/queues.
- Control flow is realized by an additional output, next-table-address, from
each table match that provides the index of the next table to execute.
- A recombination block at the end of the pipeline pushes PHV modifications back
  into the packet.

The work advocates an implementation architecture that consists of large number
of physical pipeline stages that are mapped to a smaller number of logical RMT
stages depending on the resource needs of each logical stage.

- Factoring State: Router forwarding has several stages, each using a separate
  table, processed sequentially with dependencies, so a physical pipeline is
  natural.
- Flexible Resource Allocation Minimizing Resource Waste: The resources for a
  logical stage can vary. E.g. a firewall requires all ACLs, a core router
  requires only prefix matches, an edge router requires both. But a physical
  stage has some CPU & memory resource. The number of physical stages, N, should
  be large enough to avoid resource waste by a logical stage (max 1/N), and
  small enough to reduce wiring & power overheads. They use N=32.
- Layout Optimality: A logical stage can be assigned more memory by mapping
  multiple contiguous physical stages to it to reduce wiring overheads.

They found that the power requirement is not significant, and since most
use-cases are dominated by memory use, the coupling of processing & memory
allocation is not significant in practice.

For terabit-speed realization, the needed to restrict physical match stages to
32. The chip design limit of packet headers is 4Kb (512B). They use 370Mb SRAM
and 40Mb TCAM. Each stage may execute one instruction per field & limited to
simple arithmetic, logical & bit manipulation. The queueing system provides 4
levels of hierarchy and 2K queues per port. Each stage contains over 200 action
units, one for each field in the PHV with over 7000 action units in the chip.

To configure the RMT architecture, one needs two pieces of information:

- a parse graph that expresses permissibe header sequences
- a table flow graph that expresses the set of match tables & control flow
  between them

## Strengths

- While RMT has been in discussions, it remained theoretical without an
  existence proof of a chip design that works at terabit speeds. This paper
  contributes a concrete RMT proposal & a proof of it feasibility.
- The paper involves clever use of hardware pipelining & parallelizability to
  work at terabit speeds. Their use of memory blocks that can be ganged within
  or across stages is key to realizing the vision of reconfigurable match
  tables. The large scale use of TCAM greatly increases matching flexibility,
  and use of fully-parallel VLIW instructions is key to packet editing.

## Future Work

- This paper is a proof of concept for RMT. One can investigate different chip
  designs, including more optimizations, and remove some of the restrictions.
- Developing a compiler that maps the parse graphs & table flow graphs to the
  appropriate switch configurations & perform optimized memory allocation.
