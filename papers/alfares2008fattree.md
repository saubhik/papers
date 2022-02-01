# A Scalable, Commodity Data Center Network Architecture

Paper: [Mohammad Al-Fares, Alexander Loukissas, and Amin Vahdat. 2008. A scalable, commodity data center network architecture. SIGCOMM Comput. Commun. Rev. 38, 4 (October 2008), 63–74. DOI:https://doi.org/10.1145/1402946.1402967](https://dl.acm.org/doi/10.1145/1402946.1402967)

In 2008, data center networks consisted of a tree of routers and switches with progressively more specialized and higher-end IP switches/routers up in the hierarchy, but this resulted in topologies which supported only 50% of the aggregate bandwidth available at the edge of the network, while still incurring tremendous cost.

There were two high-level choices for building communication fabric for large-scale clusters:

- Leveraging specialized hardware and communication protocols such as InfiniBand or Myrinet. This suffered from:
    - More expensive.
    - Not natively compatible with TCP/IP applications.
- Leverage commodity Ethernet switches & routers supporting familiar management infra with unmodified apps, OSs and H/W. But aggregate cluster bandwidth scales poorly with cluster size. This suffered from:
    - Oversubscription to reduce costs.
    - Using non-commodity 10Gbps (2008) switches & routers at the higher levels to reduce oversubscription.
    - Typical single path IP routing along trees of interconnected switches means that overall cluster bandwidth is limited by the bandwidth available at the root.

The paper shows that by interconnecting commodity switches in a fat-tree architecture achieves the full bisection bandwidth of clusters consisting of 10s of 1000s of nodes. 48-port Ethernet switches is capable of providing full bandwidth to up to 27,648 nodes.

- *Scalable interconnection bandwidth*: Any host can communicate with another host at full bandwidth of its local network interface.
- *Economies of scale*: Leverage economies of scale to make cheap off-the-shelf Ethernet switches the basis for large-scale data center networks like in cluster computing.
- *Backward compatibility*: Compatibility with hosts running IP/Ethernet with minimal modifications on existing switches.

### Current Data Center Network Topologies

Based on best practices as of 2008.

#### Topology

Consisted of 2- or 3-level trees of switches or routers.

- A 3-tier design has a core tier in the tree root, an aggregation tier in the middle, and an edge tier at the leaves. Supports ~10,000 hosts.
- A 2-tier design has only the core tier and the edge tier. Supports 5000-8000 hosts.

Two types of switches are used:

- 48-port GigE with four 10 GigE uplinks at the edge
- 128-port 10 GigE switches at the core

#### Oversubscription

Oversubscription is the ratio of the worst case achievable aggregate bandwidth among the end hosts to the total bisection bandwidth of a particular communication topology. Typical designs are oversubscribed by a factor of 2.5:1 (400 Mbps) to 8:1 (125 Mbps) for cost reasons.

#### Multi-path Routing

Delivering full-bandwidth between arbitrary hosts requires multi-rooted tree (multiple core switches) in large clusters. So, most enterprise core switches support ECMP (Equal Cost Multi Path) routing. Without ECMP, a single rooted 128-port 10 GigE core switch with 1:1 oversubscription can support only 1,280 nodes.

ECMP performs static load splitting among flows. This suffers from:

- Doesn't account for flow bandwidth in allocation decisions leading to oversubscription for simple communication patterns
- ECMP implementations limited path multiplicity to 8-16 (2008); larger data centers require more for higher bisection bandwidth
- Number of routing table entries grows multiplicatively with number of paths which increases cost & lookup latency

#### Cost

- The switching h/w to interconnect 20,000 hosts with full bandwidth (1:1) among all hosts costs USD 37,000,000 (2008). A Fat-tree built from only 48-port GigE switches would support 27,648 hosts at 1:1 oversubscription for USD 8,640,000 (2008).
- There is no requirement of higher speed uplinks in the fat-tree topology.
- It is technically infeasible to build a 27,648-node cluster with 10 GigE switches without fat-tree architecture, even though it would cost over USD 690,000,000 (2008).

#### Clos Networks/Fat-Trees

Charles Clos of Bell Labs designed a network topology that delivers high b/w for many end devices by interconnecting smaller commodity telephone switches in 1953. Fat-tree is a special instance of Clos topology.

A $k$-ary fat tree has:

- $k$ pods, each containing
    - two layers of $k/2$ switches (edge layer and aggregation layer)
    - each $k$-port switch in lower layer (edge layer) is connected to $k/2$ hosts, and $k/2$ upper-layer (aggregation layer) switches
- $(k/2)*2$ $k$-port core switches
    - each core switch has $i$th port connected to $i$th pod such that consecutive ports in the aggregation layer of each pod switch are connected to core switches on $(k/2)$ strides.

A fat-tree built with $k$-port switches supports $\frac{k^3}{4}$ hosts.

Advantages:

- All switching elements can be homogeneous (not required) enabling use of cheap commodity switches even at the core.
- Fat-trees are rearrangeably non-blocking: For arbitrary communication patterns, there is some set of paths that will saturate all the bandwidth available to the ends hosts (1:1 oversubscription). In practice, we might need to trade this off for avoiding TCP packet reordering at end host.
- All hosts connected to same edge switch forms their own subnet (this traffic is switched, no routing)

Challenges:

- IP/Ethernet networks typically use single routing path between source and destination. The paper describes simple extension to IP forwarding to leverage high fan-out in fat-trees.
- Significant wiring complexity. The paper presents packaging and placement techniques to mitigate.

### Architecture

Achieving maximum bisection bandwidth (1:1) requires spreading outgoing traffic from any pod as evenly as possible among the core switches. There are $(k/2)^2$ shortest paths between any two hosts on different pods. Routing needs to take advantage of this path redundancy.

#### Addressing

- All IP addresses allocated within $10.0.0.0/8$ block.
- Pod switches are allocated $10.pod.switch.1$ where $pod$ is the pod number in $[0,k-1]$ from left to right, $switch$ is $[0,k-1]$ from left to right, bottom to top.
- Core switches are allocated $10.k.j.i$ where $j$ and $i$ are the switch's coordinates in the $(k/2)^2$ core switch grid (each in $[1,k/2]$, starting form top-left).
- Host address is $10.pod.switch.ID$ where $ID$ is in $[2,k/2+1]$ from left to right.

This might seem waste of address space, but simplifies building routing tables and actually scales to 4,200,000 hosts ($k=255$)!

#### Two-Level Routing Table

- Routing tables are modified to allow two-level prefix lookup for even-distribution. Entry in the main routing table might have an additional pointer to a small secondary table of $(suffix, port)$ entries. Entries in the primary table are left-handed, and entries in secondary table are right-handed.
- If longest-matching prefix search yields a non-terminating prefix (in main table), then the longest-matching suffix in the secondary table is found and used.
- Can be implemented efficiently in H/W using Content-Addressable Memory (CAM). A CAM can perform parallel searches among all its entries in a single clock cycle. A Ternary CAM (TCAM) can store *don't care* bits in addition to matching 0s and 1s in particular positions, making it suitable for storing variable length prefixes found in routing tables. But CAMs have low storage density, are very power hungry, are expensive per bit. In this application, we need just $k$ entries, each 32 bits wide.
- Left-handed (prefix) entries stores in numerically smaller addresses and right-handed (suffix) entries in larger addresses and encode output of the CAM so that numerically smallest matching address is output.

#### Routing Algorithm

- Pod switches: The edge layer & aggregation layer acts as filtering traffic diffusers: they have terminating prefixes to the subnets in the pod. For other outgoing inter-pod traffic, the pod switches have a default $/0$ prefix with a secondary table matching host IDs:
    - This causes traffic to be evenly spread upwards among outgoing links to the core switches.
    - Also causes subsequent packets to same destination host to follow same path avoid packet reordering.
- Core switches: Contains only terminating $/16$ prefixes pointing to their destination pods.
- No switch in the network contains a table with more than $k$ first-level prefixes or $k/2$ second-level suffixes.
- If two flows from same source subnet are destined to same destination subnet, single-path IP routing would route both flows to same path which eliminates fan-out benefits of fat-tree. The two-level routing avoids this.

##### Flow Classification

This is an optional dynamic routing technique alternative to two-level routing above. This performs flow classification with dynamic port-reassignment in pod switches to overcome local congestion (two flows competing for same output port in presence of another equal cost port).

A flow is a sequence of packets with the same entries for a subset of fields of the packet headers (e.g. source and destination IP addresses, destination port).

Pod switches performs flow classification:

- Recognize subsequent packets of same flow and forward them on the same outgoing port. This avoids packet reordering.
- Periodically reassign a minimal number of flow output ports to minimize disparity between aggregate flow capacity of different ports. This ensures fair distribution on flow on upward-pointing ports in the face of dynamically changing flow sizes.

#### Flow Scheduling

The distribution of transfer times and burst lengths of internet traffic is long tailed. Routing large long-lived flows plays most important role in determining achievable bisection bandwidth of a network. We want to schedule large flows to minimize overlaps with one another.

- Edge switches: Assigns a new flow to least-loaded port initially. Sends periodic notifications to a central scheduler specifying the source and destination of all active large flows. This is a request for placement of that flow in an uncontended path.
- Central scheduler (replicated): Tracks all flows and tries to assign them non-conflicting paths if possible. Linearly searches through the $(k/2)^2$ core switches (corresponding to each equal cost path), and finds one whose path components do not include a reserved link. Garbage collects old flows and reservations.

#### Fault Tolerance

We can leverage the path redundancy between any two hosts. Each switch maintains a Bidirectional Forwarding Detection (BFD) session with each neighbor. We need redundancy at edge-layer to tolerate edge failures.

- Failure in edge-to-aggregation link
    - Traffic type 1: outgoing inter- and intra-pod to edge switch: this switch sets cost of broken link to infinity and never assigns it to new flows.
    - Traffic type 2: intra-pod traffic to aggregation switch: this switch broadcasts a tag notifying all other edge switches in same pod to not use the broken link.
    - Traffic type 3: inter-pod traffic to aggregation switch: this switch broadcasts a tag to all core switches to not use the broken link. The core switches can mirror the tag to all other aggregation switches in other pods to not use the broken link.

- Failure in aggregation-to-core link
    - Traffic type 1: outgoing inter-pod traffic to aggregation switch: this switch removes link from local routing table and locally chooses another core switch.
    - Traffic type 2: incoming inter-pod traffic to core switch: core switch broadcasts tag to all other aggregation switches in other pods to avoid using the broken link.

This mechanism is reversed when failed links and switches come back up and reestablish their BSD sessions.

#### Power and Heat Issues

- 10 GigE switches consume roughly double the Watts/Gbps and dissipate roughly 3x heat of commodity GigE switches. This is two more reasons to use commodity switches. (2008)
- For an interconnect supporting ~27,000 hosts, the fat-tree architecture uses more switches (2,880 Netgear GSM 7252S) but with 56.6% less power consumption and 56.5% less heat dissipation than typical hierarchical designs (576 ProCurve 2900 edge switches and 54 BigIron RX-32 switches, 36 in aggregation and 18 in core).

### Implementation, Evaluation & Results

- They implemented a prototype using NetFPGAs. The NetFPGA contains an IPv4 router implementation that leverages TCAMs. The routing table lookup routine modifications totaled < 100 LOC and introduced no measurable lookup latency.
- They built a prototype using Click, a modular software router architecture that supports implementation of experimental router designs.
- To measure the total bisection bandwidth of fat-tree design, they generate a benchmark suite of communication mappings to evaluate the performance of the 4-port fat-tree using two-level routing, flow classification, and flow scheduling and compared to a standard hierarchical tree with a 3.6:1 oversubscription.
- With dynamic flow assignment and re-allocation, the flow classifier outperforms both the traditional tree & two-level table with a worst case bisection bandwidth of ~75%. It is imperfect because it avoids only local congestions.
- The flow scheduler acts on global knowledge and tries to assign large flows to disjoint paths, achieving 93% of ideal bisection bandwidth for random communication mappings.

### Packaging

Increased wiring overhead is inherent to the fat-tree topology. They present an approach in the context of 27,648-node cluster with 48-port GigE switches where each pod consists of 576 machines and 48 switches. Suppose each host takes 1RU (1 Rack Unit) and 1 rack can accommodate 48 machines. There are 576 core switches.

- Each pod has 12 racks of 48 machines each.
- All the 48 switches in the pod are packed in a single monolithic unit with 1,152 user-facing ports.
    - 576 of these 1152 ports connect directly to machines.
    - 576 of these 1152 ports fan out to one port on each of the 576 core switches.
    - 1152 internal ports are wired to other switches in the same pod (edge-aggregation interconnects).
- Each of the 48 pods houses 12 core switches.
    - Of the 576 cables from a packed pod switch rack, 12 connects directly to core switches place near the pod.
    - The rest fans out to other pods in sets of 12 to core switches housed in remote pods.

The cable sets move in sets of 12 from pods to pod and in sets of 48 from racks to pod switches. This is opportunity for cable packaging to reduce wiring complexity.

The 12 racks can be placed around pod switch rack in two dimensions to reduce cable length. The 48 pods can be layed out in a 7x7 grid to reduce inter-pod cabling distance and can support standard cable lengths & packaging.

## Strengths & Weaknesses

### Strengths

- The paper presents a novel and important contribution to data center cluster interconnections. The paper solves the scalable bandwidth problem which affected data centers in a cost effective manner. The authors bring the cluster-computing idea of displacing expensive, high-end machines by clusters of commodity PCs to data center interconnects by leveraging large number of commodity GigE switches to displace high-end switches. Even though the fat-tree topology is not novel (used for telephone switching), the authors solve the architectural and implementation challenges of standard IP single-path routing using novel IP addressing scheme and two-level routing mechanism that require minimal modification to existing switches without breaking backward compatibility of TCP/IP/Ethernet stack prevalent in data centers.
- Also, they alleviate the ECMP challenge of static load splitting of flows which disregards flow bandwidth by proposing their own simple flow classification by dynamic port reassignment, which is stateful but can fall back to two-level routing in case of lost state. In addition, they attempt to maximize achievable bisection bandwidth by introducing flow scheduling to direct large flows to use uncontended paths, and also introduces simple fault tolerance schemes to tolerate link and switch failures.
- They acknowledge the problem of power and heat issues which is an important practical consideration in deployments of new technologies in the data center. They provide sufficient empirical evidence for their case of using larger number of commodity switches against expensive, high-end switches.

### Weaknesses

- Flow scheduling is impractical in real-world deployments. The use of a centralized scheduler with knowledge of all active flows and the status of all links is infeasible for large arbitrary networks. The regularity of the fat-tree topology can simplify the search for disjoint, uncontended paths but this study is not undertaken. Flow scheduling as they do it is infeasible.
- They attempt to solve the cabling problem with clever packaging. But they make some good number of assumptions: each host takes up 1RU, individual racks accommodating 48 machines, and packing 48 switches in a single rack. This puts constraint on the data center operator to trade away some other placement requirements to accommodate the fat-tree interconnect requirements.
- The experiments in power and heat issues are not made in real deployments of the design. It would be interesting to see if the real world deployments conform with their findings. There might be other practical overheads associated with using a large number of commodity switches.

## Follow-on

- As mentioned in the weaknesses, one important follow-on is to investigate more practical designs for the flow scheduling problem at hyperscalar scale. At large scales, it is infeasible to maintain the required large state for their described mechanism to work.
- Study the practical (power, heat, cooling issues) in a realistic deployment of the fat-tree design. It would be interesting to find issues not mentioned in the paper.
- Investigate the performance with fault tolerance mechanisms like Bidirectional Forwarding Detection (BFD) active in a real data-center deployment. The achievable bisection bandwidth would correspond to more realistic values.

---

<script type="text/javascript" async
  src="https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.1/MathJax.js?config=TeX-MML-AM_CHTML">
</script>
