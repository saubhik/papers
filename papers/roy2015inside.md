# Inside the Social Network's (Datacenter) Network

Paper: [Arjun Roy, Hongyi Zeng, Jasmeet Bagga, George Porter, and Alex C. Snoeren. 2015. Inside the Social Network's (Datacenter) Network. In Proceedings of the 2015 ACM Conference on Special Interest Group on Data Communication (SIGCOMM '15). Association for Computing Machinery, New York, NY, USA, 123–137. DOI:https://doi.org/10.1145/2785956.2787472)](https://dl.acm.org/doi/10.1145/2785956.2787472)

<!--

Contents:
- [ ] Abstract
- [ ] Introduction
- [ ] Related Work
- [ ] A Facebook DC
    - [ ] DC topology
    - [ ] Constituent services
    - [ ] Data collection
        - [ ] Fbflow
        - [ ] Port mirroring
- [ ] Provisioning
    - [ ] Utilization
    - [ ] Locality and stability
    - [ ] Traffic matrix
    - [ ] Implications for connection fabrics
- [ ] Traffic Engineering
    - [ ] Flow characteristics
    - [ ] Load balancing
    - [ ] Heavy hitters
    - [ ] Implications for traffic engineering
- [ ] Switching
    - [ ] Per-packet features
    - [ ] Arrival patterns
    - [ ] Buffer utilization
    - [ ] Concurrent flows
- [ ] Conclusion

-->

## Summary

This paper reports on properties of network traffic in Facebook's datacenters such as locality, stability and predictibility, and also discusses the implications for network architecture, traffic engineering, and switch design. The paper also finds that while traditional datacenter services like Hadoop follow behaviors reported earlier, the core Web service and supporting cache infrastructure exhibit a number of behaviors that contrast with those reported in the literature. This study is the first to report on production traffic in a datacenter network connecting hundreds of thousands of 10-Gbps nodes.

Using both Facebook-wide monitoring systems and per-host packet-header traces, the study examine services that generate the majority of the traffic in Facebook's network. Major findings in this study are:

- Traffic is neither rack-local nor all-to-all. Locality depends upon the service but is stable across time periods from seconds to days. Efficient fabrics may benefit from variable degrees of oversubsription and less intra-rack bandwidth than typically deployed.
    - This contrasts previously published data that 50-80% of traffic is rack-local.
    - This potentially impacts datacenter fabrics

- Many flows are long-lived but not very heavy. Load balancing distributes traffic across hosts effectively making traffic demands quite stable over even sub-second intervals. As a result, heavy hitters are not much larger than the median flow, and the set of heavy hitters changes rapidly. Instantaneously heavy hitters are frequently not heavy over longer time periods and this confounds many approaches to traffic engineering.
    - This contrasts previously published data that demain is frequently concentrated and bursty.
    - This potentially impacts traffic engineering.

- Packets are small (median length for non-Hadoop traffic is less than 200 bytes) and do not exhibit on/off arrival behavior. Servers communicate with 100s of hosts and racks concurrently (within the same 5-ms interval), but the majority of traffic is often destined to (few) 10s of racks.
    - This contrasts previously published data of bimodal ACK/MTU packet size, on/off arrival behavior, and <5 concurrent large flows.
    - This potentially impacts SDN controllers, circuit/hybrid switching.

### Datacenter Topology

- Facebook's network consists of multiple datacenter sites and a backbone connecting these sites. Each datacenter site contains one or more datacenter buildings where each datacenter contains multiple clusters. A cluster is a unit of deployment.
- Machines are organized into racks and connected to a top-of-rack switch (RSW) via 10-Gbps Ethernet links. The number of machines per rack varies from cluster to cluster.
- Each RSW is connected by 10-Gbps links to four aggregation switches called cluster switches (CSWs). All racks served by a particular set of CSWs are said to be in the same cluster.
- Clusters may be homogeneous in terms of machines. e.g. cache clusters, or heterogeneous, e.g. Frontend clusters which contain a mixture of Web servers, load balancers, and cache servers.
- CSWs are connected to each other via another layer of aggregation switches called Fat Cats (FC). This design follows directly from the need to support a high amount of intra-cluster traffic.
- CSWs also connect to aggregation switches for intra-site (inter-datacenter) traffic and datacenter routers for inter-site traffic.

Every machine typically has one role:

- Web servers serve Web traffic
- MySQL servers store user data
- query results are stored temporarily in cache servers including
    - leaders, which handle cache coherency, and
    - followers, which serve most read requests
- Hadoop servers handle offline analysis and data mining
- Multifeed servers assemble news feeds

### Data Collection

The study considers two distinct data sources:
- Fbflow is a production monitoring system that samples packet headers from Facebook's entire machine fleet. In production use, it aggregates statistics at a per-minute granularity.
- To collect high-fidelity data, they collect traces by turning on port mirroring on the RSW and mirroring the full, bi-directional traffic for a single server to collection server. Since `tcpdump` is unable to handle more than approximately 1.5 Gbps of traffic, so in order to support line-rate traces, they employ a custom kernel module that effectively pins all free RAM on the server and uses it to buffer incoming packets.

*Limitations:*

- Using end hosts to capture and timestamp packets introduces scheduler-based variations on timestamp accuracy.
- Traffic can only be captured from a few hosts at a time without risking drops in packet collection.
- These constrains prevent evaluating effects like incast or microbursts which lead to poor application performance.
- Per-host packet dumps are anecdotal and ad hoc, relying on the presence of an unused capture host on the same rack as the target.

### Provisioning

The study quantifies the traffic intensity, locality and stability across three different types of clusters: Hadoop, Frontend machines serving Web requests and Cache.

#### Utilization
- The overall access link (i.e. links between hosts and their RSW) utilization is quite low, with the average 1-minute link utilization less than 1%.
- Demand follows typical diurnal and day-of-the-week patterns, although the magnitude of change is on the order of 2x.
- Load varies considerably across clusters, with Hadoop clusters having 5x average link utilization than Frontend clusters.
- Utilization rises at higher levels of aggreagtion (between RSWs and CSWs, and between CSWs and FCs).

#### Locality and stability
- Hadoop traces show both rack- and cluster-level locality. This pattern is consistent with previous observations in which traffic is either rack-local or destined to one of roughly 1-10% of the hosts in the cluster. From traffic matrix, they found Hadoop traffic is cluster-local (more than 80%), as opposed to rack-local (14%).
- Traffic patterns for other server classes are stable with lack of rack-local traffic and large quantities of inter-datacenter traffic. This contrasts previous observations.
    - Frontend cache followers primarily send traffic (response) to Web servers, leading to high intra-cluster traffic (serving cache reads). Load balancing spreads this traffic widely.
    - Cache leaders maintain coherency across clusters and the backing DB, leading to intra- and inter-datacenter traffic.
    - Strong bipartite traffic pattern between Web servers and cache followers in Webserver racks, within the cluster. This is because Web servers talk primarily to cache servers and vice versa, and server of different types are deployed in distinct racks leading to low intra-rack traffic.
- Relative proportions of locality is stable, but the toal amount of traffic may change due to diurnality

The authors give a concrete argument for this locality. Loading the Facebook news feed draws from a vast array of different objects in the social graph: different people, relationships and events comprise a large graph interconnected in a complicated fashion. This connectedness means that the working set is unlikely to reduce even if users are partitioned; the net result is a low cache hit rate within the rack, leading to high intra-cluster traffic locality.

*Implications for connection fabrics:*

- The highly contrasting locality properties of the different clusters imply a single homogeneous topology will either be over-provisioned in some regions or congested in others. Non-uniform fabric technologies that can deliver higher bandwidth to certain locations than others may be useful.
- Rapid reconfigurability may not be necessary because of the stability of traffic patterns.
- The lack of intra-rack locality suggest that RSWs that deliver less than full non-blocking line-rate connectivity between all their ports may be viable.

### Traffic Engineering

- Flow characteristics:
    - Most flows in Facebook's Hadoop cluster are short. The median flow sends less than 1 KB and last less than a second.
    - Most flows are long-lived due to heavy use of connection pooling in Facebook's internal services, and pooling is prevalent in cache follower/leader nodes.
    - Most flows are active (actually transmit packets) only during distinct millisecond-scale intervals with large intervening gaps. Thus, flows are internally bursty.
    - Web server flows lie between cache flows and Hadoop flows.
- Facebook's load balancing is highly effective on timescales lasting minutes to hours, leaving less room for traffic engineering. Hadoop (not load balances) shows wide variation in flow rates and it is this variability of traffic that existing traffic engineering schemes seek to leverage.
- Other flows (Web servers and cache) rates are stable, both over time and by destination, due to combination of workload characteristics and engineering effort. The offered load per second is roughly held constant to a cache system - large increased in load would indicate presence of relatively hot objects, which is actively monitored and mitigated.

*Heavy hitters:*

Heavy hitters represent the minimum set of flows (or hosts, or racks in the aggregated case) that is responsible for 50% of the observed traffic volume (in bytes) over a fixed time period. Heavy hitters signify an imbalance than can be acted upon. The study finds it challenging to identify heavy hitters that persist with any frequently. This situation results from a combination of effective load balancing (little difference in size between a heavy hitter and the median flow) and the relatively low long-term throughput of most flows (even heavy flows can be quite bursty internally).

### Switching

- Hadoop traffic is bimodal: almost all packets are either MTU length (1500 bytes) or TCP ACKs. Packets for other services have median size less than 200 bytes.
- While link utilization is low, the packet rate is high. A cache server at 10% link utilization with a median packet size of 175 bytes generates 85% of the packet rate of a fully utilized link sending MTU-sized packets. Any per-packet operation may be stressed.
- Hosts in Facebook's datacenter do not exhibit on/off arrival pattern, even within Hadoop clusters. This maybe due to large number of concurrent destinations.
- The combination of a lack of on/off traffic, higher flow intensity, and bursty individual flows increase buffer utilization and overruns. Even though link utilization is on the order of 1% most of the time, over 2/3 of the available shared buffer is utilized during each 10-microsecond interval. Careful buffer tuning is important moving forward.
- Web servers and cache hosts have 100s to 1000s of concurrent connections, while Hadoop nodes have approximately 25 concurrent connections on average.

## Strengths & Weaknesses

### Strengths

- This study presents network traffic characteristics in datacenter for a hyperscalar internet service, along with some workload information. This is invaluable for future work on designing network fabrics to efficiently interconnect and manage the traffic within datacenters. The study comments on the limited literature regarding network traffic characteristics, and contrast the findings with previous contributions on a number of points.
- Such studies provide inspiration for future work in multiple ares of datacenter fabrics, traffic engineering, SDN controllers, and circuit/hybrid switching schemes. These studies are important to understand the problems with the current standards, and think about ways to improve on the existing strategies.
- The study provides the state-of-the-art (at the time) connection fabric used in data centers, and also tools for used for effective networking monitoring and analysis at hyperscalar scales. At these scales, conventional tools such as tcpdump cannot be used (mentioned above).

### Weaknesses

- As the study mentions, some of the results and distribution graphs are not representative of the actual traffic characteristics. This is a challenging aspect of the study and we need to take their results in faith. In some sections, the authors caution against examining the specific distributions too carefully, as traces from other nodes or even the same node at different times reveal different distributions. Understandably, it is extremely hard to extract meaningful generalization about network traffic behavior at such huge scales with the current monitoring techniques.
- The methodology imposes a few limitations on the scope of the study. As mentioned before, using end hosts to capture and timestamp packets introduces scheduler-based variations on timestamp accuracy. In addition, one can only capture traffic from a few hosts at a time without risking drops in packet collection. These constraints prevent from evaluating effects like incasts or microbursts. Per-host packet dumps are anecdotal and ad hoc, relying on the presence of an unused capture host on the same rack as the target.

## Follow-On
There are multiple immediate follow-on ideas from this work:

- Investigate the impact of using different communication fabrics with variable degrees of oversubscription, and also using top of the rack switches (RSWs) that deliver less than full non-blocking line-rate connectivity to leverage the lack of rack-local traffic.
- Hadoop shows wide variation in flow rates which existing network traffic engineering schemes can leverage. Orchestra relies on temporal and per-job variation to provide lower task completion times for high-priority tasks. Hedera provides non-interfering route placement for high bandwidth elephant flows that last for several seconds. One can study the impact of using such mechanisms.
- As utilization increases in the future, it might be through an increase in the number of flows, in the size of packets, or both. Larger packets with the same level of burstiness will use up more of the buffer. A larger number of flows leads to a greater chance of multiple flows sending bursts of packets simultaneously. Thus, we need to investigate careful buffer tuning mechanisms.
- Investigate new tools for effective networking monitoring and analysis at hyperscalar scales.

---
