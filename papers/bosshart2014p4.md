# P4: Programming Independent Packet Processors

Pat Bosshart, Dan Daly, Glen Gibb, Martin Izzard, Nick McKeown, Jennifer
Rexford, Cole Schlesinger, Dan Talayco, Amin Vahdat, George Varghese, and David
Walker. 2014. P4: programming protocol-independent packet processors. SIGCOMM
Comput. Commun. Rev. 44, 3 (July 2014), 87–95.
DOI:https://doi.org/10.1145/2656877.2656890

The promise of SDN is that a single control place can directly control a whole
network of switches. OpenFlow (OF) supports this goal by providing a single,
vendor-agnostic API. But the control plane cannot express how the packets howd
be processed to best meet the needs of control apps. OF v1.0 (Dec 2009) started
simple with abstractions of a single table of rules that could match packets on
12 header field, e.g. MAC addresses, IP addresses, protocol, TCP/UDP port
numbers, etc. OF v1.4 (Oct 2013) specification requires 41 header fields.
Datacenter network operators want to apply new forms of packet encapsulation
(e.g. NVGRE, VXLAN, STT) requiring more header fields. This requires repeatedly
extending the OF specification. Instead P4 enables supporting flexible
mechanisms for parsing packets & matching header fields, allowing controller
apps to leverage these capabilities.

The challenge is to find a sweet spot that balances:

- need for expressiveness
  - e.g. Click but it is difficult to infer dependencies & map to h/w
- ease of implementation across wide range of h/w & s/w switches
  - e.g. OpenFlow 1.0 but it is impossible to reconfigure protocol processing

P4 has three goals:

- reconfigurability in the field
  - controller can re-define packet parsing & processing in the field
- protocol independence
  - switch not tied to specific packet formats
  - controller can specify packet parser for extracting header fields with
    specific names & types
  - controller can specify a collection of typed match+action tables that
    process these headers
- target independence
  - a compiler should take switch's capabilities into account when turning a
    target-independent P4 description into a target-dependent microcode program.

The work first describes an abstract forwarding model.

Switches forward packets via a programmable parser followed by multiple stages
of match+action, arranged in series, parallel, or a combination of both.

- OF assumes a fixed parser. P4 supports a programmable parser to allow new
  headers to be defined.
- OF assumes match+action stages are in series. In P4, they can be in parallel
  or in series.
- P4 assumes actions are composed of protocol-independent primitives supported
  by the switch.

This generalizes how packets are processed on different forwarding devices -
Ethernet switches, load-balancers, routers, etc. & by different technologies -
fixed-function switch ASICs, NPUs, reconfigurable switches, s/w switches, FPGAs.
This allows using a common language, P4, to represent how packets are processed.

The forwarding model is controlled by 2 ops:

- Configure
  - program the parser
  - set the order of match+action stages
  - specify the header fields processed by each stage
  - determines which protocols are supported
- Populate:
  - add/remove entries to the match+action tables specified during configuration
  - determines the policy applied to the packets

Arriving packets are first handled by the parser. The packet body is buffered
separately, unavailable for matching. The parser extracts the fields from the
header. The extracted header fields are passed to match+action tables (ingress &
egress).

- ingress processing: forwarded, replicated (for multicast, span, or to control
  plane), dropped, or trigger flow control
- egress processing: per-instance modifications to header - e.g. for multicast
  copies

A packet processing language must allow the programmer to express any serial
dependencies between header fields. Dependencies determine which tables can be
executed in parallel. Dependencies can be identified by analyzing the Table
Dependency Graphs (TDG) which describe the field inputs, actions, and control
flow between tables.

They propose a 2-step compilation process:

- programmers express packet processing programs using an imperative language
  representing the control flow (P4)
- a compiler translates the P4 representation to TDGs to facilitate dependency
  analysis and then maps the TDG to a specific swtich target using a target
  specific back-end.

The key concepts in P4 are: headers, parsers, tables, actions, control programs.

They explore P4 by examining a simple example. They consider a L2 network
deployment with ToR switches at the edge connected by a two-tier core. The
number of end-hosts is growing and the core L2 tables are overflowing. P4 lets
us express a custom solution with minimal changes to the network architecture.
The routes through the core are encoded by a 32-bit tag.

- Header: First, we add a new header, `mTag` with fields 8-bit `up1`, `up2`,
  `down1`, `down2`, and 16-bit `ethertype`.
- Packet Parser: P4 assumes the underlying switch can implement a state machine
  that traverses packet headers from start to finish, extracting field values as
  it goes. Parsing starts in the `start` state and proceeds until an explicit
  `stop` state is reached or an unhandled case is encountered (error). The
  extracted headers are forwarded to match+action processing in the next-half of
  the switch pipeline.
- Table Specification: The programmer then describes how the defined header
  fields are matched in match+action stages (e.g. exact, prefix, wildcards,
  etc.) and what actions should be performed when a match occurs.
- Action Specification: P4 defines a collection of primitive actions from which
  more complicated actions are built. The programmer specifies the complex
  actions made up of primitive actions such as `set_field`, `copy_field`,
  `add_header`, `remove_header`, `increment`, `checksum`. P4 assumes parallel
  execution of primitives within an action function.
- Control Program: The programmer then specifies the control flow from one table
  to another via an imperative representation using functions, conditionals and
  table references.

## Strengths

- This work unlocks the potential of SDNs further by proposing a configuration
  language & compilers that generate low-level target-specific configurations
  including h/w optimizations to provide greater expressivity instead of
  repeatedly extending the OpenFlow specification to meet the needs of control
  plane applications.
- The work stresses on resolving dependencies between match+action tables to
  parallelize the execution as much as possible on the switch h/w. P4 is
  designed to make it easy to translate an imperative control program into a
  table dependency graph. The design also lets the compiler optimize for the
  specific target: support RAM & TCAM, parallel tables, few tables, final
  writes.

## Weaknesses

- SDN is successful because one can control a whole network of switches, which
  led to cost savings as well (by simplifying the switch functionality to only
  provide forwarding), even though one had to re-write interfaces for
  applications. Even though P4 supports the goal of SDN offering more
  flexibility to the controller applications, P4 would have limited or no
  benefits with low-cost targets like fixed-function switches. The potential
  targets of P4 are expensive.

## Future Work

- The work emphasizes that P4 is a first step towards more expressivity in the
  data plane. In this proposal, several aspects of a switch are undefined: e.g.
  congestion control primitives, queueing disciplines, traffic monitoring. Each
  of these are areas of future work.
