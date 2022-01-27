# High-Resolution Measurement of Data Center Microbursts

Paper: [Qiao Zhang, Vincent Liu, Hongyi Zeng, and Arvind Krishnamurthy. 2017. High-resolution measurement of data center microbursts. In Proceedings of the 2017 Internet Measurement Conference (IMC '17). Association for Computing Machinery, New York, NY, USA, 78–85. DOI:https://doi.org/10.1145/3131365.3131375](https://dl.acm.org/doi/10.1145/3131365.3131375)

This study explores fine-grained behavior of a large production data center using extremely high-resolution measurements (10-100 microseconds) of rack-level traffic.

Earlier work on data center traffic are either on the scale of minutes or are heavily sampled. The two approaches taken in earlier works are:

- Packet sampling (e.g. Facebook samples every 1 in 30,000)
- Coarse-grained counters (e.g. SNMP collection in minute-scale)

Coarse-grained measurements can inform us of long-term network behavior and communication patterns, but fail to provide insight into many important behaviors such as congestion. This study developed a custom high-resolution counter collection framework on top of the data center's in-house switch platform, and then analyzes various counters (including packet counters and buffer utilization statistics) from Top-of-Rack (ToR) switches in multiple clusters running multiple applications.

### High-resolution counter collection

Modern switches include relatively powerful general-purpose multi-core CPUs in addition to their switching ASICs. The ASICs are responsible for packet processing, and need to maintain many counters. The CPUs handle control plane logic. The CPU can poll the switch's local counters at extremely low latency, and batch the samples before sending them to a distributed collector service that is fine-grained and scalable.

The study focusses on 3 sets of counters. For each, they manually determine the minimum sampling interval possible while maintaining ~1% sampling loss.

- Byte count: Measures the cumulative number of bytes sent/received per switch port, to calculate the throughput. Sampling interval: 25 microseconds.
- Packet size: Histogram of the packet sizes sent/received at each switch port. The ASIC bins packets into several buckets. Sampling interval: 25 microseconds.
- Peak buffer utilization: Take the peak utilization since the last measurement, and reset the counter after reading. Sampling interval: 50 microseconds.

### Data set

Machines are organized into racks and connected to a ToR switch via 10 Gbps Ethernet links. Each ToR is connected to an aggregation layer of "fabric" switches via 40 or 100 Gbps links. The "fabric" switches are connected to a "spine" switches. This study focusses on the ToR switches.

Each server machine have a single role (application):

- Web: Receive web requests and assemble a dynamic web page using data from many remote sources.
- Cache: Serve as an in-memory cache of data used by the web servers. Some are leaders handling cache coherency, and some are followers, serving read requests.
- Hadoop: For offline analysis and data mining.

An entire rack is dedicated to each of these roles. Measuring at a ToR level, the results can isolate behavior of different classes of applications.

### Port-level behavior

They studied the fine-grained behavior of individual ports. A switch's egress link is hot if, for the measurement period, its utilization exceeds 50%. An unbroken sequence of hot samples indicates a burst. They choose to define a burst by throughput rather than the buffer utilization as buffers are often shared and dynamically carved, making pure byte counts a more deterministic measure of burstiness.

Findings:

- *High utilization is short lived.* The 90th percentile burst duration is < 200 microseconds. Congestion events observed by less granular measurements are likely collection of smaller microbursts.
- *Bursts are correlated.* The high-utilization intervals tend to be correlated.
- *Fine-grained measurements are needed to capture bursty behavior accurately.* The 25 microsecond measurement granularity is itself too coarse as over 60% of Web and Cache bursts terminated within that period.
- *Inter-burst periods have a much longer tail than burst durations.* Most interburst periods are small, particularly for Cache and Web racks where 40% of inter-burst periods last less than 100 microseconds, but when idle periods are persistent, the inter-burst periods last for 100s of milliseconds.
- *Bursty periods tend to include more large packets than non-bursty periods.* Hadoop sees mostly full-MTU packets. The material packet-level difference between packets inside and outside bursts suggests that bursts at the ToR layer are often a result of application-behavior changes, rather than random collisions.
- *Different applications have different utilization patterns, but all are extremely long tailed.* This suggests that when bursts occur, they are generally intense.

### Cross-port behavior

They studied the synchronized behavior of switch ports. Each switch's port can be split into 2 classes: uplinks and downlinks. The uplinks connect the rack to the rest of the data center, and modulo network failures, they are symmetric in both capacity and reliability. Downlinks connect to individual servers, which all serve similar role.

ToR switches use Equal-Cost MultiPath (ECMP) to spread load over each of their 4 uplinks. ECMP configurations introduce at least 2 sources of potential imbalance in order to avoid TCP reordering:

- ECMP operates on the level of flows, rather than packets
- ECMP uses consistent hashing, which cannot guarantee optimal balance

Findings:

- *Uplinks are unbalanced at small timescales.* The instantaneous efficacy of load balancing impact drop- and latency-sensitive protocols like RDMA and TIMELY. The imbalance (Mean Absolute Deviation, MAD, of the four uplink utilizations) is large (p50 over 25%) at small timescales (40 microseconds). This indicates flow-level load balancing can be inefficient in the short term.
- *The interconnect does not add significant variance.* The ingress and egress traffic for the ToR switch exhibits a similar pattern (MAD of egress vs ingress traffic).
- *Downlink utilization balance depends on application.* Web servers run stateless services that are entirely driven by user requests, so correlation is zero (balanced). Subsets of the Cache servers show very strong correlation with one another (imbalanced). This is because their requests are initiated in groups from web servers, and hence those subsets are involved in the same scatter-gather requests.
- *Direction of bursts depends on application.* For Web and Hadoop racks, hot downlinks are more frequent due to high fan-in where many servers send to a single destination. Cache servers have more frequent hot uplinks than downlinks because of two properties: (1) they exhibit simple response-to-request communication pattern, and (2) cache responses are much larger than the requests.
- *Peak buffer occupancy depends on application.* Hadoop puts significantly more stress on ToR buffers than either Web or Cache racks, and buffer occupancy scales with the number of hot ports. Buffer occupancy levels off for high numbers of hot ports.

## Strengths & Weaknesses

### Strengths

- This study has implications for network measurement, design and evaluation of new network protocols and architectures. As network bandwidth continues to rise in data centers, the timescale of network events will decrease accordingly. It is essential to understand high-resolution behavior of these networks. At these small timescales, traffic is extremely bursty, load is unbalanced, and different applications have different behavior.
- The study required non-trivial engineering work to implement a low-latency sampling framework built on top of an in-house switch platform. It required manually determining the sampling intervals with minimal sampling loss. Along with the engineering, the study also rigorously establishes correlation between consecutive bursts using the likelihood ratio test, and theoretically rejects the hypothesis that burst arrivals are Poisson.

### Weaknesses

- The paper presents the numbers and findings for fine-grained port-level & synchronized network traffic behavior extensively, but does not put much effort in providing reasoning for the findings extensively. The results presented in the paper gives insight into the degree of the problem in practice, but does not attempt to solve any of the issues presented.
- No comparisons with long-term traffic behavior were made. It would have been more interesting to see the comparison with similar studies made with coarse-grained measurements, on the same deployment.

## Implications & Follow-On

Avenues for possible future work:

- *load balancing.* Load balancing on microflows rather than 5-tuples - splitting a flow as soon as the inter-packet gap is long enough to guarantee no reordering. This is viable as inter-burst periods typically exceed end-to-end latencies. However, faster networks may decrease this gap.
- *congestion control.* Traditional CC algorithms either react to packet drops, RTT variation, or ECN as congestion signal. All of these signals require at least RTT/2 to arrive at sender, and protocol might take multiple RTTs to adapt. But large number of microbursts are shorter than single RTT. Buffering is viable to handle momentary congestion but lower-latency congestion signals may be required.
- *pacing.* TCP pacing was one of the original mechanisms that prevented bursty traffic, but has been rendered ineffective through new features like segmentation offload, interrupt coalescing. Recent pacing proposals may be worth considering either at the hardware or software level.

Other follow-on ideas:

- Domain knowledge suggests than application-level demand and traffic patterns are a significant contributor to bursts. But to study this as a cause of burstiness would require correlating and synchronizing switch and end hosts measurements at a microsecond level.
- The study focusses on ToR switches, and leaves the study of other network tiers ("fabric" and "spine" switches) to future work. It would be interesting to see the network traffic behavior at these aggregate-level switches.

---
