# Understanding Lifecycle Management Complexity of Datacenter Topologies

Paper: [Mingyang Zhang, Radhika Niranjan Mysore, Sucha Supittayapornpong, and Ramesh Govindan. 2019. Understanding lifecycle management complexity of datacenter topologies. In Proceedings of the 16th USENIX Conference on Networked Systems Design and Implementation (NSDI'19). USENIX Association, USA, 235–254.](https://www.usenix.org/system/files/nsdi19-zhang.pdf)

Data center networks are important facilities for cloud computing and there is a long line of work on topology design:

- A Clos is a multi-rooted tree with layered structure which can scale to arbitrary size with low radix merchant silicon switching chips, readily deployed in practice.
- There is another family of topologies called expanders. Expander graph can use much smaller number of switches to achieve the same performance compared to Clos. For example:
  - *Jellyfish* (NSDI 12) is a degree bounded random graph,
  - *Xpander* (CoNEXT 16) is a clique of metanodes. A metanode is a cluster of switches without links between each other.

Previous designs focussed on achieving high performance at low cost, but not much attention to designing for manageability. This work considers management complexity of data center topology design.

How does the complexity of managing data centers depend on the topology? This work focuses on studying lifecycle management of data center topologies. *Life cycle management* is the process of building a network, physically deploying it on the data center floor and expanding it over several years so that it is available for use by a constantly increasing set of services.

Lifecycle management complexity is important:

- Complex deployment can stall the rollout of new services for a long time. This is expensive considering the increasing traffic demand.
- Topology expansion leads to capacity drop due to rewiring. Complex expansion leads to network functioning with degraded capacity for a long time.

To understand lifecycle management there are several challenges to be solved:

- *How to characterize the management complexity?*
  The study proposes some metrics to quantify lifecycle management complexity by considering practical, physical constraints.
- *How does topology structure affect the management complexity?*
  By leveraging the developed metrics, the paper compared several topology families and found that no topology dominates by all the metrics. They derive some principles on achieving low lifecycle management complexity.
- *Is there a topology family with low management complexity, low cost and high performance?*
  By leveraging the learned principles, the paper designs a new topology family called FatClique which achieves all the nice properties at the same time.

## Characterizing management complexity

Many dimensions to lifecycle management: packaging, cable wiring, placement, cable rewiring during expansion. All these problems need to respect constraints from all kinds of data center devices such as switches, racks, patch panels, cable trays.

They derive metrics that capture the complexity of deployment and expansion of topologies.

### Quantifying deployment complexity

*Packaging Metric: Number of switches*

Packaging is the first step in deployment. Packaging is carefully arranging servers and switches into the data center rack. The number of switches directly determine packaging complexity, so this is used as a metric.

*Wiring Complexity Metric: Number of cable bundle types (bundle capacity, bundle length)*

After packing servers and switches into racks, they are connected. If the connected switches are within the same rack, we can use short and cheap cables to connect them. If connected switches are in different racks and far from each other on the data center floor, we use inter-rack links, which are routed over cable trays over the data center racks. The main wiring complexity comes from the inter-rack links.

In data center scales, there are too many fibers to be handled individually. So we use cable bundling. A cable bundle is a fixed number of identical-length fibers between two clusters of network devices, characterized by capacity (number of fibers in bundle) and length.

If the number of bundle types increase, we can expect that the complexity of manufacturing, packaging and cable routing can increase. So we use number of bundle types as a metric to quantify the wiring complexity.

*Wiring Complexity Metric: Number of patch panels*

Patch panel is a network device that acts as an aggregator. It is a device where fibers from different bundles are connected manually.

### Quantifying expansion complexity

Topology expansion leads to capacity drop. To maintain a given residual capacity, topology expansion is conducted in multiple steps. The *number of expansion steps* is a natural metric to quantify expansion complexity.

### Quantifying single expansion step complexity

It is hard to move existing links which has already been routed over cable trees. To solve this, patch panels are used. First, all existing bundles are connected to some patch panel. During expansion, we need to connect the new links to the existing patch panels. We can complete the rewiring process entirely on the patch panels. But this rewiring is manual, dominating the time for each expansion step. So, they use the *number of rewired links per patch panel rack* as a metric to quantify single expansion step complexity.

## Comparison of topologies

The paper studies Clos, Jellyfish and Xpander. Clos performs better in terms of patch panel usage and bundling. Jellyfish performs better in terms of switches, re-wired links per patch panel rack & expansion complexity. No topology dominates by all the metrics.

### Three principles to achieve low management complexity

*Principle 1: Importance of topology regularity*

Jellyfish is a random graph which leads to non-uniform bundles between switch clusters. In large scale, Jellyfish has 1 order of magnitude more bundle types than Clos.

*Principle 2: Importance of maximizing intra-rack links*

In Clos, some regular part with dense links can be packed into a single rack. These links are cheap, short and easy to manage. But, most links in Jellyfish are inter-rack links, which leads to more patch panel usage & high wiring complexity.

*Principle 3: Importance of fat edge*

Fat edge can significantly reduce the expansion capacity. The network edge can be divided it's out-links into two categories: links connecting servers called southbound links, and links connecting switches are called northbound links. A thin edge has equal number of northbound and southbound links. A fat edge has more northbound links than southbound links.

Suppose, we want to keep residual capacity during expansion at 75%. Since rewiring leads to capacity drop, we need to drain traffic before rewiring. For thin edge, to maintain residual capacity, we can drain & rewire at most 25% links at the edge leading to 25% capacity drop. For fat edge, even draining 50% link leads to 0 capacity drop. So, more links can be rewired in a single expansion step.

Jellyfish has fat-edge so it has fewer expansion steps while Clos has thin-edge and hence more expansion steps.

## FatClique, a new topology family

FatClique is a topology with 3 hierarchies. In the lowest hierarchy, they build a sub-block (clique of switches) with the design goal of packing multiple sub-blocks into a single rack to maximize intra-rack links. In the second hierarchy, they build the blocks which is a clique of sub-blocks. They compose a whole network with a clique of blocks with the design goal of large enough blocks to form uniform bundles between each other.

By construction, FatClique satisfies the regularity principle. But maximizing intra-rack links and achieving fat edge is conflicting. To achieve fat-edge, we need to decrease the intra-rack links per switch in a sub-block. Achieving fat edge also conflicts with minimizing switch usage.

There are other constraints in topology design such as providing right amount of capacity, minimizing rack fragmentation, minimizing overall cable length, etc.

The solution is a *constraint-based search*. The whole design space can be described by 5 variables. An example is imposing a fat edge at a switch: \#northbound links > \#southbound links. They use this formulation to search a topology with a given capacity and optimal manageability objectives.

## FatClique Evaluation

They designed highly optimized placement algorithm, topology expansion algorithm, topology search algorithm for each topology families. They evaluate different topology families in large scale. FatClique performs best in all deployment complexity metrics.

Also, FatClique is as good as expanders. It only uses 3 or 4 expansion steps even when the residual capacity requirement is tight. For Clos, the residual capacity requirement is very high and requires more than 20 steps to expand the whole topology. Thus, FatClique enables higher availability.

In particular, FatClique uses 50% fewer switches, 33% fewer patch panels than Clos at large scale, 23% lower cabling cost, and can permit fast expansion while degrading network capacity by small amounts (2.5 - 10%), while Clos can take 5x longer to expand the topology, each Clos expansion step requires 30-50% more links to be rewired at each step per patch panel.

## Strengths & Weaknesses

### Strengths

- This work is a first step towards designing for manageability, which is a critical dimension in data center topology design. The paper designs several metrics to quantify the management complexity. The paper uses the principles learned from the existing topology families, to design a new topology family with same-performance and faring well in all the management complexity metrics.

- The study developed quite a few optimal algorithms for various competing topology families: Clos generation, Jellyfish placement, FatClique expansion, optimal expansion solutions for Clos, FatClique topology synthesis and also quantified other properties of the topologies: Spectral Gap to approximate Edge Expansion, and number of shortest paths between two ToR switch from different pods in Clos and computing the number of paths no longer than this in other topologies to compute the path diversity. Jellyfish, Xpander and FatClique have similar and higher path diversity than Clos, and have shorter paths than Clos.

### Weaknesses

- The theoretical metric to quantify latency is network diameter. Even though FatClique has a smaller diameter, but does not have many shortest paths. This study has not considered practical routing in their design, and so cannot conclude about the latency for FatClique.

- Even though the management complexity metrics they come up with aids in deciding about competing topology designs, it would be more helpful if the study could get cost-performance numbers for each design. Big data center operators could provide some ballpark numbers for translating the complexity metrics to cost, and then the cost-performance curves would be interesting to study.

## Future Work

The paper leaves good pointers for further work on manageability of data center topology designs:

- Topology Oversubscription. The study only considers topologies with an over-subscription ratio of 1:1. Jupiter permits over-subscription at edge, but there is anecdotal evidence that providers also over-subscribe at higher levels in Clos topologies. To study manageability of over-subscribed networks, it is necessary to design over-subscription techniques in FatClique, Xpander and Jellyfish to have a fair comparison.
- Topology Heterogeneity. Topologies accrue heterogeneity over time: new blocks with higher radix switches, patch panels with different port counts etc. These complicate lifecycle management. Data-driven models need to be developed for how heterogeneity accrues in topologies over time and complexity metrics need to be adapted.
- How to deal with other network management problems like control plane complexity, network debug-ability, practical routing for FatClique?
