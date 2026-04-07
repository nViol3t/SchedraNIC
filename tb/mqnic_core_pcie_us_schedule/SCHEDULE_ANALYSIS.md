# mqnic_core_pcie_us_schedule 分析说明

## 1. 这个目录在做什么

这个目录是一个基于 `cocotb` 的联合仿真测试环境，用来验证你修改过的 `mqnic` 网卡发送调度路径。

它不是只测普通收发，而是重点验证：

- 软件侧是否能把每个 TX 包的 `rank` 和 `wqe` 写进硬件
- 硬件侧是否能把这些 doorbell 送入 PIFO
- PIFO 是否按 `rank` 选出下一次应发送的队列
- 被调度出的队列是否真正走完 `desc_fetch -> tx_engine -> MAC -> loopback/RX` 这条链

当前目录实际顶层测试文件是：

- `mqnic.py`
- `test_mqnic_core_pcie_us.py`

当前目录里没有 `mqnic_core_pcie_us_schedule.py`；实际承担顶层测试功能的是 `test_mqnic_core_pcie_us.py`。

## 2. 关键文件角色

### 2.1 Python 侧

#### `mqnic.py`

这是 cocotb 侧的软件驱动模型，主要负责：

- 枚举 NIC 寄存器块
- 初始化 EQ/CQ/TXQ/RXQ
- 通过 PCIe BAR 配置网卡
- 发包、收包

你对它的关键改动是增加了队列寄存器：

- `MQNIC_QUEUE_RANK_WQE = 0x14`

发送时在 `Txq.write_prod_ptr()` 中会：

1. 先写 `MQNIC_QUEUE_RANK_WQE`
2. 再写 `SET_PROD_PTR`

写入格式为：

- `rank << 3 | wqe`

也就是：

- 高 13 bit 为 `rank`
- 低 3 bit 为 `wqe`

#### `test_mqnic_core_pcie_us.py`

这是 cocotb 顶层测试脚本，主要负责：

- 搭建 PCIe Root Complex 和 Xilinx UltraScale+ PCIe 设备模型
- 初始化以太网 MAC 模型
- 初始化驱动并打开 TX/RX 队列
- 运行调度相关测试

当前默认执行的是：

- `test_wf2q(tb, interface)`

其他两个测试：

- `test_ping(tb, interface)`
- `test_strict_priority(tb, interface)`

目前在 `run_test_nic()` 中没有启用。

## 3. RTL 主线

### 3.1 顶层替换点

在 `../../rtl/mqnic_core.v` 中，接口模块已经替换成：

- `mqnic_interface_change`

这说明当前仿真跑的是你改过调度路径的 NIC，不是原始接口实现。

### 3.2 `mqnic_interface_change.v`

这是你改造后的接口主模块。它的关键作用是：

- 接入 `tx_queue_manager_change`
- 接入 PIFO
- 将 PIFO 的输出接回 TX 请求路径
- 将 TX 结果再反馈给 `tx_queue_manager_change`

核心连接关系是：

1. `tx_queue_manager_change` 输出带 `rank/wqe` 的 doorbell
2. `mqnic_interface_change` 把 doorbell 作为 PIFO 的 push 输入
3. PIFO pop 出当前最优调度项
4. 该调度项送给 `mqnic_interface_tx`
5. `mqnic_interface_tx` 发起 descriptor request
6. `desc_fetch` 从 TX queue 取描述符
7. `tx_engine` 执行 DMA 读取并发包

PIFO 的 push 数据格式是：

- `{{tx_doorbell_rank, global_ts}, tx_doorbell_queue, tx_doorbell_tag, tx_doorbell_wqe}`

这说明调度键不是只有 `rank`，还叠加了：

- `global_ts`

因此：

- 主排序键是 `rank`
- 同 rank 情况下用 `global_ts` 作为 tie-breaker

### 3.3 `tx_queue_manager_change.v`

这是你自定义的 TX 队列管理器，是整个调度改造的核心。

它相对原版 queue manager 增加了三件事：

- doorbell RAM，保存每个 queue 的 `(rank, wqe)`
- 每个 queue 自己的 doorbell producer/consumer 指针
- 与 PIFO 的输入输出握手

它的行为可以概括为：

1. 软件写 queue doorbell 寄存器，把 `rank+wqe` 写进 doorbell RAM
2. 如果该 queue 当前没有待调度 doorbell，就直接把这一项送入调度入口
3. 如果该 queue 已有活跃 doorbell，则新的项先缓存
4. 当前活跃 doorbell 被 PIFO 消费后，再从该 queue 的 doorbell RAM 中取下一项补进 PIFO

换句话说：

- PIFO 看到的是“每个 queue 当前可参与竞争的队首项”
- 每个 queue 的后续项先存在本地 doorbell RAM 里

这保持了：

- 队列内部顺序
- 队列之间按 `rank` 做全局竞争

## 4. 发送调度路径

完整路径如下：

1. Python 调用 `interface.start_xmit(pkt, qid, rank=...)`
2. `mqnic.py` 把描述符写到 TX ring
3. `mqnic.py` 再把 `rank+wqe` 写到 `MQNIC_QUEUE_RANK_WQE`
4. `tx_queue_manager_change` 记录 doorbell，并把候选项送向 PIFO
5. PIFO 选出全局最优的 `(queue, tag, wqe)`
6. `mqnic_interface_tx` 根据这个结果发起 descriptor dequeue
7. `desc_fetch` 从 TX queue 取出相应 descriptor
8. `tx_engine` 做 DMA read，把数据送到 MAC
9. MAC 发出的帧在测试中被 loopback 或 peer stack 接收
10. 完成后相关状态反馈回来，允许该 queue 的下一个 doorbell 进入 PIFO

## 5. 测试在验证什么

### 5.1 `test_ping`

这个测试不是调度重点，而是验证整个 NIC 的基础收发链路。

测试中 cocotb 会模拟一个线端对端主机：

- 收到 ARP request 就回 ARP reply
- 收到 ICMP echo-request 就回 echo-reply

这说明它是功能正确性测试。

### 5.2 `test_strict_priority`

这个测试给不同 queue 分配不同固定 `rank`。

测试意图是验证：

- `rank` 小的 queue 是否先发完
- 实际收包顺序是否符合严格优先级

它最终会生成：

- `sp.png`
- `sp.pdf`
- `sp_data.xlsx`

### 5.3 `test_wf2q`

这是当前默认运行的测试。

注意：这里硬件里并没有实时计算 WF2Q。

真实做法是：

1. 测试脚本先按 queue 的 `weight` 计算虚拟完成时间
2. 把虚拟完成时间量化成 `rank`
3. 再把这个 `rank` 写给硬件
4. 硬件只负责做“按 rank 排序”

因此，这套硬件更准确地说是：

- 一个通用的 rank-based scheduler

而不是：

- 在 RTL 内部完整实现 WF2Q 算法

该测试会生成：

- `wf2q.png`
- `wf2q.pdf`
- `wf2q_data.xlsx`

## 6. 回环方式

这个目录里有两种回包方式：

### 6.1 `loopback_enable`

在 `_run_loopback()` 中：

- 监听 `mac.tx`
- 直接把帧送回 `mac.rx`

这用于 `test_strict_priority` 和 `test_wf2q`。

优点是：

- 包确实经过 DUT 的 TX datapath 和 RX datapath
- 可以直接观察不同 queue 的发送次序

### 6.2 `peer_stack()`

这个是软件模拟的线端协议栈，用于：

- ARP 响应
- ICMP ping 响应

它主要服务于 `test_ping`。

## 7. 仿真入口

本目录 `Makefile` 已配置好仿真入口，默认：

- `SIM ?= icarus`
- `DUT = mqnic_core_pcie_us`
- `MODULE = test_mqnic_core_pcie_us`

并且会编入：

- `../../rtl/tx_queue_manager_change.v`
- `../../rtl/mqnic_interface_change.v`
- `../../rtl/Pifo_Sram_old/PIFO_SRAM_Top.sv`

因此这个目录本身就是针对你当前调度设计的专用仿真目录。

## 8. 一句话总结

这个目录在做的是：

通过 cocotb 搭建完整 PCIe + Ethernet + mqnic 联合仿真环境，验证你对 mqnic TX 调度路径的改造是否有效。软件侧为每个包写入 `rank+wqe`，硬件侧通过 `tx_queue_manager_change + PIFO` 按 `rank` 做全局调度，当前默认测试是把 WF2Q 结果预先编码成 `rank` 后检查实际发包顺序是否符合预期。
