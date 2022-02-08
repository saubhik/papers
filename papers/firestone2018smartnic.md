# Azure Accelerated Networking: SmartNICs in the Public Cloud

*Paper:* [Daniel Firestone, Andrew Putnam, Sambhrama Mundkur, Derek Chiou, Alireza Dabagh, Mike Andrewartha, Hari Angepat, Vivek Bhanu, Adrian Caulfield, Eric Chung, Harish Kumar Chandrappa, Somesh Chaturmohta, Matt Humphrey, Jack Lavier, Norman Lam, Fengfen Liu, Kalin Ovtcharov, Jitu Padhye, Gautham Popuri, Shachar Raindel, Tejas Sapre, Mark Shaw, Gabriel Silva, Madhan Sivakumar, Nisheeth Srivastava, Anshuman Verma, Qasim Zuhair, Deepak Bansal, Doug Burger, Kushagra Vaid, David A. Maltz, and Albert Greenberg. 2018. Azure accelerated networking: SmartNICs in the public cloud. In Proceedings of the 15th USENIX Conference on Networked Systems Design and Implementation (NSDI'18). USENIX Association, USA, 51–64.](https://dl.acm.org/doi/10.5555/3307441.3307446)

This paper presents Azure Accelerated Networking (AccelNet), a solution for offloading host networking to hardware using custom Azure SmartNICs based on FPGAs, providing <15 microseconds VM-VM TCP latencies and 32 Gbps throughput, since 2016.

Azure has built its cloud network on host-based SDN technologies, through software running in the hypervisor, to implement a rich & changing set of virtual networking features, in order to sell Infrastructure-as-a-Service (IaaS).

- private virtual networks with customer supplied address spaces
- scalable L4 load balancers
- security groups & Access Control Lists (ACLs)
- virtual routing tables
- bandwidth metering
- QoS

and more.

The *Virtual Filtering Platform (VFP)* is a cloud-scale programmable vSwitch, providing scalable SDN policy for Azure. It is highly programmable and serviceable.

*Single Root I/O Virtualization (SR-IOV)* reduces CPU utilization by allowing VM to directly access NIC hardware. The host connects to a privileged physical function (PF), while each virtual machine connects to its own virtual function (VF). An SR-IOV NIC contains an embedded switch to forward packets to the right VF based on the MAC address.

*Generic Flow Tables (GFT)* is a match-action language that defines transformation & control operations on packets for a specific network flow. This mechanism is used in VFP to enforce policy & filtering in an SR-IOV environment.

**The Need & Desired Goals**

Burning CPUs for these services takes away from the processing power available to customer VMs and increases the overall cost of providing cloud services. The authors need a cost-effective solution providing hardware-like performance with software-like programmability with the following goals:

- *Don't burn host CPU cores for network processing.*
  A single physical core with 2 hyper-threads is worth $4500 (2016) for an IaaS provider.
- *Maintain host SDN programmability of VFP.*
  Competitive edge of Azure for providing highly-configurable & feature-rich virtual networks to IaaS customers
- *Achieve the latency, throughput, and utilization of SR-IOV hardware.*
- *Support new SDN workloads and primitives over time.*
- *Rollout new functionality to entire fleet.*
- *Provide high single-connection performance.*
  With software-based SDN, single core network processing cannot achieve 40Gbps+ bandwidth.
- *Have a path to scale to 100Gb+.*
- *Retain serviceability.*

### Deciding the right hardware - FPGAs as SmartNICs

- ASICs provide high performance but lack programmability, and adaptability. Takes 1-2 years from specifications to arrival.
- Embedded cores in ASICs become a performance bottleneck & requires vendor-specific firmware updates.
- SoCs are easier to program and performant for 10GbE NICs. But requires lot of cores & bad single-flow performance at higher speeds of 40GbE+. Not scalable to 100GbE+.
- FPGAs can take advantage of application characteristics to configure logic blocks and memories, and hence are programmable. They give performance & efficiency of customized hardware & deep processing pipelines improve single-flow performance.
- Cost & performance overheads of burning host CPU cores are very high.

### Design & Architecture

- They augmented the current SR-IOV compatible NIC with the FPGA, and developed the FPGA to offload the SDN functionality. The FPGA is in between the NIC and the ToR switch, making it a network filter. It is also connected by 2 Gen3x8 PCIe connections to the CPUs for AI & web search accelerator workloads (Gen 1).
- Control plane remains unchanged handled by VFP in host hypervisor. Only data plane offloaded to FPGA.
- NIC driver augmented with GFT Lightweight Filter (LWF) driver abstracting details of split NIC/FPGA hardware from VFP & makes it appear as a single NIC with SR-IOV and GFT support.
- FPGA contains GFT Engine which might not contain matching rule for a packet, in which case the FPGA will send the packet to the hypervisor's vPort in the SR-IOV NIC (monitored by VFP) as an Exception Packet (first packet of a flow). VFP determines appropriate policy for the packet's flow & performs necessary flow creation tasks.
- GFT implementation on FPGA has 2 deeply pipelined packet processing units each with 4 major stages: store & forward packet buffer, parser, flow lookup & match, and flow action. The Parser parses aggregated header from each packet and outputs a unique key for each flow. Matching block computes Toeplitz hash of the key and indexes into a 2-level caching system. Action block uses parameter looked up from flow table and performs the transformations on the packet header.
- Software-programmable QoS guarantees like rate limiting can be implemented as components of the processing pipeline.
- GFT keeps track of all per-connection byte/flow counters, h/w timestamps of packets in each flow & periodically transmits all flow state state to VFP via DMA transfers over PCIe.
- GFT maintains generation ID of policy state & tracks it when rules for each flow were created. On policy update to VFP, the generation ID on the SmartNIC is incremented, and then the flows are updated lazily by marking first packet of each flow as an Exception Packet.
- *Online serviceability:* TCP flows and vNICs survive FPGA reconfiguration, FPGA driver updates, NIC PF driver updates, & GFT driver updates. When the VF comes up, the synthetic NIC driver (NetVSC) marks VF as its slave & leverages transparent bonding to make the TCP/IP stack completely transparent to the current data path. During servicing, all transmit traffic switches to the synthetic path. They included a failsafe PMD (Poll Mode Driver) to act as a bond between the VF PMD & synthetic PMD, exposing DPDK APIs for safe failover to non-accelerated code path during servicing.

### Performance

- For 1-way latency between two Windows Server 2016 VMs & sending 1 million 4-byte pings sequentially over active TCP connections
  - With a tuned software stack without AccelNet, average of 50 microseconds, with a P99 around 100 microseconds, and P99.9 around 300 microseconds.
  - With AccelNet, average of 17 microseconds with P99 of 25 microseconds, and P99.9 of 80 microseconds - much lower latency and variance.
- With pairs of both Ubuntu 16.04 VMs and Windows 10 VMs with TCP congestion control set to CUBIC and 1500 Byte MTU, VM-VM single-connection throughput is 31Gbps on 32Gbps network, with 0% associated host CPU utilization. Without AccelNet, single connection is 5Gbps & need ~8 connections on multiple cores to achieve line rate.
- AccelNet has lowest latencies, highest throughput, lowest tail latencies when compared with other public cloud offerings.
- Power draw of the Gen1 board is at 17-19W depending on traffic load, well below the 25W allowed for PCIe expansion slot.

## Strengths & Weaknesses

### Strengths

- The paper detailed the Azure SmartNIC, a FPGA-based programmable NIC, as well as Accelerated Networking, a service for high performance network providing cloud-leading network performance. Both Azure SmartNICs and AccelNet have been deployed at scale for multiple years, 3-4 years, with 100s of 1000s of customer VMs across Azure flee. So, the design choices both in the hardware and the software & system design made in this paper were extremely successful in improving network performance without impacting serviceability and reliability.
- The paper also stressed on the non-technical but critical issue of divide between hardware and software development practices and teams, & attempted to solve them, some of which can be credited to the use of FPGA.
  - The paper devotes considerable sections to convince the host networking team to adopt the use of FPGA as a SmartNIC as they were not in the business of digital logic design or SystemVerilog programming.
  - The authors mention that hardware devs should be in the same team as software devs for successful hardware/software co-design such as the SmartNIC.
  - They treated and shipped hardware logic as if it was software. Going through iterative rings of software qualification means they didn't need ASIC levels of specification & verification upfront & could be more agile.

### Weaknesses

- The paper heavily stresses on serviceability as an important operationalization metric for large-scale deployment of a solution. They have implemented fallback mechanisms to fall back to a non-accelerated code path during servicing the FPGA SmartNIC or driver updates. But, for RDMA applications this serviceability is harder, and they rely on the RDMA application characteristic of graceful fallback to TCP to close all RDMA queue pairs. This is more of a future work: app-level transparency for RDMA serviceability if apps have a hard dependency on RDMA queue pairs staying alive.

## Future Work

- This paper describes functions which were being done in hypervisor software (VFP) and offloaded to the hardware for greater performance. Future work will need to investigate new functionality that can be supported due to the presence of programmable NICs on every host.
- Investigate mechanisms for app-level transparency for RDMA serviceability if apps have a hard dependency on RDMA queue pairs staying alive. (see above)

---
