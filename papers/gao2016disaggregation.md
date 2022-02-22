# Network Requirements for Resource Disaggregation

[Peter X. Gao, Akshay Narayan, Sagar Karandikar, Joao Carreira, Sangjin Han,
Rachit Agarwal, Sylvia Ratnasamy, and Scott Shenker. 2016. Network requirements
for resource disaggregation. In <i>Proceedings of the 12th USENIX conference on
  Operating Systems Design and Implementation</i> (<i>OSDI'16</i>). USENIX
  Association, USA, 249–264.](https://dl.acm.org/doi/10.5555/3026877.3026897)

Recent industry trends suggest a paradigm shift to a disaggregated datacenter
(DDC) architecture containing a pool of resources, each built as a standalone
resource blade and interconnected using a network fabric. This work derives the
minimum latency and bandwidth requirements that the network in DDCs must provide
to avoid degrading app-level performance & explores the feasibility of meeting
these requirements with existing system designs and commodity networks, in the
context of 10 workloads spanning 7 open-source systems:

- Hadoop
- Spark
- GraphLab
- Timely dataflow
- Spark Streaming
- memcached
- HERD
- SparkSQL

The workloads can be classified into two classes based on their performance
characteristics.

- Class A: Hadoop Wordcount, Hadoop Sort, Graphlab, & Memcached
- Class B: Spark Wordcount, Spark Sort, Timely, SparkSQL BDB, HERD

The work makes the following assumptions:

- Hardware Architecture:
  - Partial CPU-memory disaggregation: Each CPU blade retains some amount of
    local memory that acts as a cache for remote meory dedicated for cores on
    that blade.
  - Cache coherence domain is limited to a single compute blade: An external
    network fabric is unlikely to support the latency & bandwidth requirements
    for inter-CPU cache coherence.
  - Resource Virtualization: Each resource blade must support virtualization of
    its resources for logical aggregations into higher-level abstractions such
    as VMs or containers.
  - Scope of disaggregation: Either rack or datacenter-scale. This is a "design
    knob". In a hypothetical DC-scale disaggregated system, resources assigned
    to a single VM could be selected from anywhere in the DC.
  - Network designs: This depends on the assumed scope of disaggregation.
    Existing DDC prototypes use specialized, proprietary network designs.
    
- System Architecture:
  - System abstractions for logical resource aggregations: VMs. We can implement
    resource allocation & scheduling in terms of VMs. Depends on scope of
    disaggregation: for rack-scale, a VM is assigned resource from within a
    single rack, and for DC-scale, a VM is assigned resources from anywhere in
    the DC.
  - Hardware organization: "Mixed" organization in which each rack hosts a mix
    of different types of resource blades, as opposed to a "segregated"
    organization in which a rack is populated with a single resource type. This
    leads to more uniform communication patterns & permits optimizations to
    localize communication.
  - Page-level remote memory access: Assume CPU blades access remote memory at
    page-granularity (4KB in x86) instead of the typical memory access between
    CPU and DRAM occurs in unit of a cache-line size (64B in x86). This exploits
    spatial locality in memory access patterns.
  - Block-level distributed data placement: Apps in DDC reads/writes large files
    at sector-granularity (512B in x86). The disk block address space is
    range-partitioned into blocks, uniformly distributed across disk blades.

The design knobs in the study are:

- the amount of local memory on compute blades
- the scope of disaggregation (either rack-scale or DC-scale)

For I/O traffic to storage devices, the current latency & b/w requirements allow
us to consolidate them into the network fabric with low performance impact,
assuming we have a 40Gbps or 100Gbps network. The dominant impact to app
performance comes from CPU-memory disaggregation.

The work compares the performance of apps in a server-centric architecture to
its performance in the disaggregated context (represents the worst-case in terms
of potential degradation, compared to re-write). To emulate remote memory
accesses, they implement a special swap device backed by some amount of physical
memory rather than disk, and intercept all page faults & injects artificial
delays to emulate network RTT latency and bandwidth for each paging operation.
This does not model queueing delays.

The work shows the following:

- For Class A apps, a network with end-to-end latency of 5 micros & b/w of 40
  Gbps is sufficient for performance penalty within 5%. Class B apps require
  network latencies of 3 micros & b/w 40-100 Gbps for performance penalty within
  10%. Performance for Class B apps is very sensitive to network latency. 
  - They show that end-to-end latencies estimated fail to meet the target
    latencies for either Class A or Class B apps. The overhead of network
    software is the key barrier to realizing disaggregation with current
    networking technologies. They consider two potential optimizations and
    technologies to reduce latencies (& integrating them):
      - Using RDMA. RDMA bypasses the packet processing in the kernel
        eliminating the OS overheads.
      - Using NIC integration. Integrating the NIC functions closer to the CPU
        reduces the overheads associated with copying data to/from the NIC.
  - After assuming RDMA + NIC Integration, Class A jobs can be scheduled at
    blades distributed across the DC, Class B jobs will need to scheduled within
    a rack.
  - New links & switches would bring cross-rack latency down enough to enable
    true DC-scale disaggregation (along with RDMA + NIC Integration).
  - Managing network congestion to achieve 0 or close-to-0 queueing is
    essential.

- Increasing b/w beyond 40 Gbps offers little improvement in app-level
  performance. This is easily met: 40Gbps are available in commodity DC switches
  & server NICs.

- Increasing the amount of local memory beyond 40% has little to no impact on
  performance degradation. This requirement is feasible: compatible with
  demonstrated h/w prototypes.

- Overall memory b/w is well correlated with resultant performance degradation.
  Thus, an app's memory b/w requirements serves as a rough indicator of its
  expected degradation under disaggregation without requiring any
  instrumentation.

The work then evaluates the impact of queueing delay. They collect a remote
memory access trace from their instrumentation tool: a network access trace
using tcpdump and a disk access trace using blktrace. Then, they translate these
traces to network flows in their simulated disaggregated cluster. They consider
five protocols and use simulation to evaluate their network-layer performance
measured in FCT (Flow Completion Time) under the generated traffic workloads:

- TCP
- DCTCP, which leverages ECN (Explicit Congestion Notification)
- pFabric, prioritizes short flows
- pHost, emulates pFabric but using scheduling at the end hosts
- FastPass, a centralized scheduler that schedules every packet

They find the following:

- The relative ordering in mean slowdown is consistent with prior results but
  their absolute values are higher. This is due to differences in traffic
  workloads used in original measurements.
- pFabric performs best, and they use pFabric FCTs as the memory access times in
  the emulation (as artificial delays).
- Inclusion of queuing delay does have a non-trivial impact on performance
  degradation. 100 Gbps links are both required and sufficient to contain the
  performance impact of queuing delay.

The authors also built a kernel-space RDMA block device driver which serves as
swap device. The local CPU can now swap to remote memory instead of disk.

- They batch block requests sent to RDMA NIC.
- They merge requests with contiguous addresses into a single large request.
- They allow asynchronous RDMA requests: created a data structure to keep track
  of outgoing requests & notify the upper layer immediately for each completed
  request.
- The software overhead of swapping is 2.46 microseconds on a commodity Linux
  desktop. This suggests that low-latency access to remote memory can be
  realized.

## Strengths

- This paper is an early work for network requirements for disaggregation and is
  the earliest effort at evaluation the minimum bandwidth & latency requirements
  that the network in disaggregated datacenters must provide. They keep
  app-level performance degradation within 5% and also discuss about the
  feasibility of their findings with existing network designs & technologies.
- They use a clever combination of emulation, simulation & implementation for
  doing this study. This is challenging because there is no real disaggregated
  environment and much more harder in an academic environment. They use an
  extensive suite of 10 workloads (without modifying their server-centric
  architecture) spanning 7 open-source systems.

## Weaknesses

- Approaches such as Fastpass which introduces a centralized scheduler
  scheduling every packet is impractical in datacenter settings. They also
  optimistically assume that the scheduler's decision logic incurs no overhead.
  These assumptions will likely not hold true in a practical setting.
- Their evaluation results might be impacted by testbed-centric interferences.
  Even though they run experiments on Amazon EC2 cluster and enable EC2's
  Virtual Private Network capability in their cluster to ensure no interference
  with other instances, there might be testbed-induced bias in the results. But,
  this is the best one can do for such a study.

## Future Work

There are numerous directions for future work:

- Generalization of the results in the paper to other systems and workloads.
- Design and implementation of a "disaggregation-aware" scheduler.
  - In particular, based on the type of application (Class A or Class B), the
    scheduler should be able to resource allocate according to the scope of
    disaggregation: rack-scale or DC-scale, for maximum app-level performance.
- Adoption of low-latency network software & hardware at endpoints.
  - Such as high-bandwidth links, high-radix switches, optical switches.
- Creation of new programming models that exploit disaggregation.
  - One direction is for apps to exploit the availability of low-latency access
    to large pools of remote memory.
  - Another direction is for improving performance through better resource
    utilization. Current CPU-to-memory utilization for tasks in today's DCs
    varies by 3 orders of magnitudes - one can "bin pack" on a larger scale and
    DDCs should achieve more efficient statistical multiplexing.

