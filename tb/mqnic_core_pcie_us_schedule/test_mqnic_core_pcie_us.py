# SPDX-License-Identifier: BSD-2-Clause-Views
# Copyright (c) 2021-2023 The Regents of the University of California

import itertools
import logging
import os
import struct
import sys

import pandas as pd
import random

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

import scapy.utils
from scapy.layers.l2 import Ether, ARP
from scapy.layers.inet import IP, ICMP, UDP
from scapy.packet import Raw

import cocotb_test.simulator
import pytest

import cocotb
from cocotb.log import SimLog
from cocotb.clock import Clock
from cocotb.result import SimTimeoutError
from cocotb.triggers import RisingEdge, FallingEdge, Timer, Combine

from cocotbext.axi import AxiStreamBus
from cocotbext.axi import AxiSlave, AxiBus, SparseMemoryRegion
from cocotbext.eth import EthMac
from cocotbext.pcie.core import RootComplex
from cocotbext.pcie.xilinx.us import UltraScalePlusPcieDevice

try:
    import mqnic
except ImportError:
    # attempt import from current directory
    sys.path.insert(0, os.path.join(os.path.dirname(__file__)))
    try:
        import mqnic
    finally:
        del sys.path[0]


SCHED_TEST_PKT_SIZE = 1024
SCHED_TEST_LINK_SPEED = 25e9
SCHED_TEST_PKT_COUNT = 100
WF2Q_SEND_TIMEOUT_US = 2000
WF2Q_RECV_TIMEOUT_US = 100

# Pastel color palette for scheduler tests
PASTEL_COLORS = [
    '#FFB3B3',  # Q0 - light red
    '#B3D4FF',  # Q1 - light blue
    '#B3FFB3',  # Q2 - light green
    '#D9B3FF',  # Q3 - light purple
    '#FFD699',  # Q4 - light orange
    '#FFFFB3',  # Q5 - light yellow
    '#D9B3A3',  # Q6 - light brown
    '#FFB3D9',  # Q7 - light pink
    '#D9D9D9',  # Q8 - light gray
    '#B3E6D9',  # Q9 - light teal
]

def create_legend_figure(queue_configs, prefix="scheduler_legend"):
    """Create a standalone legend figure with all queue colors."""
    fig, ax = plt.subplots(figsize=(12, 3))
    ax.axis('off')

    handles = [mpatches.Patch(color=cfg['color'], label=cfg['name'])
               for cfg in queue_configs]
    ax.legend(handles=handles, loc='center', ncol=len(queue_configs),
              fontsize=12, frameon=True, fancybox=True, shadow=True)

    plt.savefig(f"{prefix}.png", dpi=150, bbox_inches="tight",
                facecolor='white', edgecolor='none')
    plt.savefig(f"{prefix}.pdf", bbox_inches="tight",
                facecolor='white', edgecolor='none')
    print(f"Legend saved: {prefix}.png / {prefix}.pdf")
    plt.close()
    return fig


def build_sched_test_pkt(qid, seq, size=SCHED_TEST_PKT_SIZE):
    if size < 5:
        raise ValueError("Scheduler test packet size must be at least 5 bytes")
    return bytearray([qid]) + seq.to_bytes(4, 'little') + bytearray([0] * (size - 5))


def constant_pause_generator(value):
    while True:
        yield value


def set_interface_tx_pause(tb, interface, paused):
    first = interface.index * interface.port_count
    last = first + interface.port_count

    for mac in tb.port_mac[first:last]:
        if paused:
            mac.tx.stream.set_pause_generator(constant_pause_generator(True))
        else:
            mac.tx.stream.clear_pause_generator()
            mac.tx.stream.pause = False


async def send_queue_burst(tb, interface, qid, pkt_entries, sent_counts, timeout_us=WF2Q_SEND_TIMEOUT_US, label="SCHED"):
    total = len(pkt_entries)

    for idx, entry in enumerate(pkt_entries, start=1):
        await cocotb.triggers.with_timeout(
            interface.start_xmit(entry['pkt'], qid, rank=entry['rank']),
            timeout_us, 'us'
        )

        sent_counts[qid] = idx

        if idx == 1 or idx == total or idx % 10 == 0:
            tb.log.info(
                "%s send progress: Q%d %d/%d sent (seq=%d rank=%d)",
                label, qid, idx, total, entry['seq'], entry['rank']
            )


async def receive_scheduler_packets(tb, interface, queue_configs, total_pkts, label, timeout_us=WF2Q_RECV_TIMEOUT_US, debug_limit=10):
    recv_data = []
    recv_seqs = {cfg['qid']: set() for cfg in queue_configs}
    expected_seqs = {cfg['qid']: set(range(cfg['count'])) for cfg in queue_configs}

    try:
        for pos in range(total_pkts):
            pkt = await cocotb.triggers.with_timeout(interface.recv(), timeout_us, 'us')
            qid = pkt.data[0]
            seq = int.from_bytes(pkt.data[1:5], 'little')
            recv_seqs[qid].add(seq)
            recv_data.append({'pos': pos, 'qid': qid, 'seq': seq})

            if pos < debug_limit:
                tb.log.info(f"{label} DEBUG: pos={pos}, qid={qid}, seq={seq}")
            if (pos + 1) % 25 == 0 or pos == 0:
                tb.log.info(f"{label} progress: {pos+1}/{total_pkts} received")
                for cfg in queue_configs:
                    q = cfg['qid']
                    tb.log.info(f"  Q{q}: {len(recv_seqs[q])}/{cfg['count']}")

    except SimTimeoutError:
        tb.log.error(f"{label} TIMEOUT at pos={len(recv_data)}, only received {len(recv_data)}/{total_pkts} packets")
        for cfg in queue_configs:
            qid = cfg['qid']
            missing = expected_seqs[qid] - recv_seqs[qid]
            tb.log.error(f"  Q{qid}: received {len(recv_seqs[qid])}/{cfg['count']}, missing seqs: {sorted(missing)[:20]}")
        raise

    all_ok = True
    for cfg in queue_configs:
        qid = cfg['qid']
        missing = expected_seqs[qid] - recv_seqs[qid]
        if missing:
            all_ok = False
            tb.log.error(f"{label} missing Q{qid}: {sorted(missing)[:10]}")

    return recv_data, recv_seqs, expected_seqs, all_ok


def create_metric_scatter(recv_data, metric_lookup, queue_configs, prefix, title, ylabel, export_excel=True):
    fig, ax = plt.subplots(figsize=(11, 6.5))
    ax.set_title(title, fontsize=16, fontweight='bold')

    for cfg in queue_configs:
        qid = cfg['qid']
        xs = [pkt['pos'] for pkt in recv_data if pkt['qid'] == qid]
        ys = [metric_lookup[(pkt['qid'], pkt['seq'])] for pkt in recv_data if pkt['qid'] == qid]
        if xs:
            ax.scatter(xs, ys, s=28, alpha=0.8, color=cfg['color'], label=cfg['name'])

    ax.set_xlabel("Reception Position", fontsize=14)
    ax.set_ylabel(ylabel, fontsize=14)
    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(f"{prefix}.png", dpi=300, bbox_inches="tight")
    plt.savefig(f"{prefix}.pdf", bbox_inches="tight")
    print(f"\n✓ Saved: {prefix}.png / {prefix}.pdf\n")

    if export_excel:
        try:
            rows = []
            for pkt in recv_data:
                rows.append({
                    'Position': pkt['pos'],
                    'Queue': pkt['qid'],
                    'Seq': pkt['seq'],
                    ylabel: metric_lookup[(pkt['qid'], pkt['seq'])],
                })
            pd.DataFrame(rows).to_excel(f"{prefix}_data.xlsx", index=False)
        except ImportError:
            print("⚠ pandas or openpyxl not installed. Skipping Excel export.")
        except Exception as e:
            print(f"⚠ Failed to export Excel: {e}")

    plt.show()


class TB(object):
    def __init__(self, dut, msix_count=32, force_eth_speed=None):
        self.dut = dut

        self.log = SimLog("cocotb.tb")
        self.log.setLevel(logging.INFO)
        self.force_eth_speed = force_eth_speed

        # Keep test progress visible while suppressing verbose bus-model logs.
        logging.getLogger("cocotb.pcie").setLevel(logging.WARNING)
        logging.getLogger("cocotb.eth").setLevel(logging.WARNING)
        logging.getLogger("cocotb.port_tx_inst").setLevel(logging.WARNING)
        logging.getLogger("cocotb.port_rx_inst").setLevel(logging.WARNING)
        logging.getLogger(f"cocotb.tb.{dut._name}").setLevel(logging.WARNING)
        logging.getLogger(f"cocotb.{dut._name}").setLevel(logging.WARNING)

        # PCIe
        self.rc = RootComplex()
        self.rc.log.setLevel(logging.WARNING)

        self.rc.max_payload_size = 0x1  # 256 bytes
        self.rc.max_read_request_size = 0x2  # 512 bytes

        self.dev = UltraScalePlusPcieDevice(
            # configuration options
            pcie_generation=3,
            # pcie_link_width=16,
            user_clk_frequency=250e6,
            alignment="dword",
            cq_straddle=len(dut.pcie_if_inst.pcie_us_if_cq_inst.rx_req_tlp_valid_reg) > 1,
            cc_straddle=len(dut.pcie_if_inst.pcie_us_if_cc_inst.out_tlp_valid) > 1,
            rq_straddle=len(dut.pcie_if_inst.pcie_us_if_rq_inst.out_tlp_valid) > 1,
            rc_straddle=len(dut.pcie_if_inst.pcie_us_if_rc_inst.rx_cpl_tlp_valid_reg) > 1,
            rc_4tlp_straddle=len(dut.pcie_if_inst.pcie_us_if_rc_inst.rx_cpl_tlp_valid_reg) > 2,
            pf_count=1,
            max_payload_size=1024,
            enable_client_tag=True,
            enable_extended_tag=True,
            enable_parity=False,
            enable_rx_msg_interface=False,
            enable_sriov=False,
            enable_extended_configuration=False,

            pf0_msi_enable=False,
            pf0_msi_count=32,
            pf1_msi_enable=False,
            pf1_msi_count=1,
            pf2_msi_enable=False,
            pf2_msi_count=1,
            pf3_msi_enable=False,
            pf3_msi_count=1,
            pf0_msix_enable=True,
            pf0_msix_table_size=msix_count-1,
            pf0_msix_table_bir=0,
            pf0_msix_table_offset=0x00010000,
            pf0_msix_pba_bir=0,
            pf0_msix_pba_offset=0x00018000,
            pf1_msix_enable=False,
            pf1_msix_table_size=0,
            pf1_msix_table_bir=0,
            pf1_msix_table_offset=0x00000000,
            pf1_msix_pba_bir=0,
            pf1_msix_pba_offset=0x00000000,
            pf2_msix_enable=False,
            pf2_msix_table_size=0,
            pf2_msix_table_bir=0,
            pf2_msix_table_offset=0x00000000,
            pf2_msix_pba_bir=0,
            pf2_msix_pba_offset=0x00000000,
            pf3_msix_enable=False,
            pf3_msix_table_size=0,
            pf3_msix_table_bir=0,
            pf3_msix_table_offset=0x00000000,
            pf3_msix_pba_bir=0,
            pf3_msix_pba_offset=0x00000000,

            # signals
            # Clock and Reset Interface
            user_clk=dut.clk,
            user_reset=dut.rst,
            # user_lnk_up
            # sys_clk
            # sys_clk_gt
            # sys_reset
            # phy_rdy_out

            # Requester reQuest Interface
            rq_bus=AxiStreamBus.from_prefix(dut, "m_axis_rq"),
            pcie_rq_seq_num0=dut.s_axis_rq_seq_num_0,
            pcie_rq_seq_num_vld0=dut.s_axis_rq_seq_num_valid_0,
            pcie_rq_seq_num1=dut.s_axis_rq_seq_num_1,
            pcie_rq_seq_num_vld1=dut.s_axis_rq_seq_num_valid_1,
            # pcie_rq_tag0
            # pcie_rq_tag1
            # pcie_rq_tag_av
            # pcie_rq_tag_vld0
            # pcie_rq_tag_vld1

            # Requester Completion Interface
            rc_bus=AxiStreamBus.from_prefix(dut, "s_axis_rc"),

            # Completer reQuest Interface
            cq_bus=AxiStreamBus.from_prefix(dut, "s_axis_cq"),
            # pcie_cq_np_req
            # pcie_cq_np_req_count

            # Completer Completion Interface
            cc_bus=AxiStreamBus.from_prefix(dut, "m_axis_cc"),

            # Transmit Flow Control Interface
            # pcie_tfc_nph_av=dut.pcie_tfc_nph_av,
            # pcie_tfc_npd_av=dut.pcie_tfc_npd_av,

            # Configuration Management Interface
            cfg_mgmt_addr=dut.cfg_mgmt_addr,
            cfg_mgmt_function_number=dut.cfg_mgmt_function_number,
            cfg_mgmt_write=dut.cfg_mgmt_write,
            cfg_mgmt_write_data=dut.cfg_mgmt_write_data,
            cfg_mgmt_byte_enable=dut.cfg_mgmt_byte_enable,
            cfg_mgmt_read=dut.cfg_mgmt_read,
            cfg_mgmt_read_data=dut.cfg_mgmt_read_data,
            cfg_mgmt_read_write_done=dut.cfg_mgmt_read_write_done,
            # cfg_mgmt_debug_access

            # Configuration Status Interface
            # cfg_phy_link_down
            # cfg_phy_link_status
            # cfg_negotiated_width
            # cfg_current_speed
            cfg_max_payload=dut.cfg_max_payload,
            cfg_max_read_req=dut.cfg_max_read_req,
            # cfg_function_status
            # cfg_vf_status
            # cfg_function_power_state
            # cfg_vf_power_state
            # cfg_link_power_state
            # cfg_err_cor_out
            # cfg_err_nonfatal_out
            # cfg_err_fatal_out
            # cfg_local_error_out
            # cfg_local_error_valid
            # cfg_rx_pm_state
            # cfg_tx_pm_state
            # cfg_ltssm_state
            cfg_rcb_status=dut.cfg_rcb_status,
            # cfg_obff_enable
            # cfg_pl_status_change
            # cfg_tph_requester_enable
            # cfg_tph_st_mode
            # cfg_vf_tph_requester_enable
            # cfg_vf_tph_st_mode

            # Configuration Received Message Interface
            # cfg_msg_received
            # cfg_msg_received_data
            # cfg_msg_received_type

            # Configuration Transmit Message Interface
            # cfg_msg_transmit
            # cfg_msg_transmit_type
            # cfg_msg_transmit_data
            # cfg_msg_transmit_done

            # Configuration Flow Control Interface
            cfg_fc_ph=dut.cfg_fc_ph,
            cfg_fc_pd=dut.cfg_fc_pd,
            cfg_fc_nph=dut.cfg_fc_nph,
            cfg_fc_npd=dut.cfg_fc_npd,
            cfg_fc_cplh=dut.cfg_fc_cplh,
            cfg_fc_cpld=dut.cfg_fc_cpld,
            cfg_fc_sel=dut.cfg_fc_sel,

            # Configuration Control Interface
            # cfg_hot_reset_in
            # cfg_hot_reset_out
            # cfg_config_space_enable
            # cfg_dsn
            # cfg_bus_number
            # cfg_ds_port_number
            # cfg_ds_bus_number
            # cfg_ds_device_number
            # cfg_ds_function_number
            # cfg_power_state_change_ack
            # cfg_power_state_change_interrupt
            cfg_err_cor_in=dut.status_error_cor,
            cfg_err_uncor_in=dut.status_error_uncor,
            # cfg_flr_in_process
            # cfg_flr_done
            # cfg_vf_flr_in_process
            # cfg_vf_flr_func_num
            # cfg_vf_flr_done
            # cfg_pm_aspm_l1_entry_reject
            # cfg_pm_aspm_tx_l0s_entry_disable
            # cfg_req_pm_transition_l23_ready
            # cfg_link_training_enable

            # Configuration Interrupt Controller Interface
            # cfg_interrupt_int
            # cfg_interrupt_sent
            # cfg_interrupt_pending
            # cfg_interrupt_msi_enable
            # cfg_interrupt_msi_mmenable
            # cfg_interrupt_msi_mask_update
            # cfg_interrupt_msi_data
            # cfg_interrupt_msi_select
            # cfg_interrupt_msi_int
            # cfg_interrupt_msi_pending_status
            # cfg_interrupt_msi_pending_status_data_enable
            # cfg_interrupt_msi_pending_status_function_num
            # cfg_interrupt_msi_sent
            # cfg_interrupt_msi_fail
            cfg_interrupt_msix_enable=dut.cfg_interrupt_msix_enable,
            cfg_interrupt_msix_mask=dut.cfg_interrupt_msix_mask,
            cfg_interrupt_msix_vf_enable=dut.cfg_interrupt_msix_vf_enable,
            cfg_interrupt_msix_vf_mask=dut.cfg_interrupt_msix_vf_mask,
            cfg_interrupt_msix_address=dut.cfg_interrupt_msix_address,
            cfg_interrupt_msix_data=dut.cfg_interrupt_msix_data,
            cfg_interrupt_msix_int=dut.cfg_interrupt_msix_int,
            cfg_interrupt_msix_vec_pending=dut.cfg_interrupt_msix_vec_pending,
            cfg_interrupt_msix_vec_pending_status=dut.cfg_interrupt_msix_vec_pending_status,
            cfg_interrupt_msix_sent=dut.cfg_interrupt_msix_sent,
            cfg_interrupt_msix_fail=dut.cfg_interrupt_msix_fail,
            # cfg_interrupt_msi_attr
            # cfg_interrupt_msi_tph_present
            # cfg_interrupt_msi_tph_type
            # cfg_interrupt_msi_tph_st_tag
            cfg_interrupt_msi_function_number=dut.cfg_interrupt_msi_function_number,

            # Configuration Extend Interface
            # cfg_ext_read_received
            # cfg_ext_write_received
            # cfg_ext_register_number
            # cfg_ext_function_number
            # cfg_ext_write_data
            # cfg_ext_write_byte_enable
            # cfg_ext_read_data
            # cfg_ext_read_data_valid
        )

        # self.dev.log.setLevel(logging.DEBUG)

        self.rc.make_port().connect(self.dev)

        self.dev.log.setLevel(logging.WARNING)

        self.driver = mqnic.Driver()
        self.driver.log.setLevel(logging.WARNING)

        self.dev.functions[0].configure_bar(0, 2**len(dut.core_pcie_inst.axil_ctrl_araddr), ext=True, prefetch=True)
        if hasattr(dut.core_pcie_inst, 'pcie_app_ctrl'):
            self.dev.functions[0].configure_bar(2, 2**len(dut.core_pcie_inst.axil_app_ctrl_araddr), ext=True, prefetch=True)

        core_inst = dut.core_pcie_inst.core_inst

        # Ethernet
        self.port_mac = []

        eth_int_if_width = len(core_inst.m_axis_tx_tdata) / len(core_inst.m_axis_tx_tvalid)
        eth_clock_period = 6.4
        eth_speed = 10e9

        if eth_int_if_width == 64:
            # 10G
            eth_clock_period = 6.4
            eth_speed = 10e9
        elif eth_int_if_width == 128:
            # 25G
            eth_clock_period = 2.56
            eth_speed = 25e9
        elif eth_int_if_width == 512:
            # 100G
            eth_clock_period = 3.102
            eth_speed = 100e9

        if self.force_eth_speed is not None:
            eth_speed = float(self.force_eth_speed)
            self.log.info("Forcing simulated Ethernet speed to %.3f Gbps for scheduler congestion", eth_speed/1e9)

        for iface in core_inst.iface:
            for k in range(len(iface.port)):
                cocotb.start_soon(Clock(iface.port[k].port_rx_clk, eth_clock_period, units="ns").start())
                cocotb.start_soon(Clock(iface.port[k].port_tx_clk, eth_clock_period, units="ns").start())

                iface.port[k].port_rx_rst.setimmediatevalue(0)
                iface.port[k].port_tx_rst.setimmediatevalue(0)

                mac = EthMac(
                    tx_clk=iface.port[k].port_tx_clk,
                    tx_rst=iface.port[k].port_tx_rst,
                    tx_bus=AxiStreamBus.from_prefix(iface.interface_inst.port[k].port_inst.port_tx_inst, "m_axis_tx"),
                    tx_ptp_time=iface.port[k].port_tx_ptp_ts_tod,
                    tx_ptp_ts=iface.interface_inst.port[k].port_inst.port_tx_inst.s_axis_tx_cpl_ts,
                    tx_ptp_ts_tag=iface.interface_inst.port[k].port_inst.port_tx_inst.s_axis_tx_cpl_tag,
                    tx_ptp_ts_valid=iface.interface_inst.port[k].port_inst.port_tx_inst.s_axis_tx_cpl_valid,
                    rx_clk=iface.port[k].port_rx_clk,
                    rx_rst=iface.port[k].port_rx_rst,
                    rx_bus=AxiStreamBus.from_prefix(iface.interface_inst.port[k].port_inst.port_rx_inst, "s_axis_rx"),
                    rx_ptp_time=iface.port[k].port_rx_ptp_ts_tod,
                    ifg=12, speed=eth_speed
                )

                self.port_mac.append(mac)

        dut.eth_tx_status.setimmediatevalue(2**len(core_inst.m_axis_tx_tvalid)-1)
        dut.eth_tx_fc_quanta_clk_en.setimmediatevalue(2**len(core_inst.m_axis_tx_tvalid)-1)
        dut.eth_rx_status.setimmediatevalue(2**len(core_inst.m_axis_tx_tvalid)-1)
        dut.eth_rx_lfc_req.setimmediatevalue(0)
        dut.eth_rx_pfc_req.setimmediatevalue(0)
        dut.eth_rx_fc_quanta_clk_en.setimmediatevalue(2**len(core_inst.m_axis_tx_tvalid)-1)

        # DDR
        self.ddr_group_size = core_inst.DDR_GROUP_SIZE.value
        self.ddr_ram = []
        self.ddr_axi_if = []
        if hasattr(core_inst, 'ddr'):
            ram = None
            for i, ch in enumerate(core_inst.ddr.dram_if_inst.ch):
                cocotb.start_soon(Clock(ch.ch_clk, 3.332, units="ns").start())
                ch.ch_rst.setimmediatevalue(0)
                ch.ch_status.setimmediatevalue(1)

                if i % self.ddr_group_size == 0:
                    ram = SparseMemoryRegion()
                    self.ddr_ram.append(ram)
                self.ddr_axi_if.append(AxiSlave(AxiBus.from_prefix(ch, "axi_ch"), ch.ch_clk, ch.ch_rst, target=ram))

        # HBM
        self.hbm_group_size = core_inst.HBM_GROUP_SIZE.value
        self.hbm_ram = []
        self.hbm_axi_if = []
        if hasattr(core_inst, 'hbm'):
            ram = None
            for i, ch in enumerate(core_inst.hbm.dram_if_inst.ch):
                cocotb.start_soon(Clock(ch.ch_clk, 2.222, units="ns").start())
                ch.ch_rst.setimmediatevalue(0)
                ch.ch_status.setimmediatevalue(1)

                if i % self.hbm_group_size == 0:
                    ram = SparseMemoryRegion()
                    self.hbm_ram.append(ram)
                self.hbm_axi_if.append(AxiSlave(AxiBus.from_prefix(ch, "axi_ch"), ch.ch_clk, ch.ch_rst, target=ram))

        dut.ctrl_reg_wr_wait.setimmediatevalue(0)
        dut.ctrl_reg_wr_ack.setimmediatevalue(0)
        dut.ctrl_reg_rd_data.setimmediatevalue(0)
        dut.ctrl_reg_rd_wait.setimmediatevalue(0)
        dut.ctrl_reg_rd_ack.setimmediatevalue(0)

        cocotb.start_soon(Clock(dut.ptp_clk, 6.4, units="ns").start())
        dut.ptp_rst.setimmediatevalue(0)
        cocotb.start_soon(Clock(dut.ptp_sample_clk, 8, units="ns").start())

        dut.s_axis_stat_tdata.setimmediatevalue(0)
        dut.s_axis_stat_tid.setimmediatevalue(0)
        dut.s_axis_stat_tvalid.setimmediatevalue(0)

        self.loopback_enable = False
        cocotb.start_soon(self._run_loopback())

    async def init(self):

        for mac in self.port_mac:
            mac.rx.reset.setimmediatevalue(0)
            mac.tx.reset.setimmediatevalue(0)

        self.dut.ptp_rst.setimmediatevalue(0)

        for ram in self.ddr_axi_if + self.ddr_axi_if:
            ram.write_if.reset.setimmediatevalue(0)

        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

        for mac in self.port_mac:
            mac.rx.reset.setimmediatevalue(1)
            mac.tx.reset.setimmediatevalue(1)

        self.dut.ptp_rst.setimmediatevalue(1)

        for ram in self.ddr_axi_if + self.ddr_axi_if:
            ram.write_if.reset.setimmediatevalue(1)

        await FallingEdge(self.dut.rst)
        await Timer(100, 'ns')

        await RisingEdge(self.dut.clk)
        await RisingEdge(self.dut.clk)

        for mac in self.port_mac:
            mac.rx.reset.setimmediatevalue(0)
            mac.tx.reset.setimmediatevalue(0)

        self.dut.ptp_rst.setimmediatevalue(0)

        for ram in self.ddr_axi_if + self.ddr_axi_if:
            ram.write_if.reset.setimmediatevalue(0)

        await self.rc.enumerate()

    async def _run_loopback(self):
        while True:
            await RisingEdge(self.dut.clk)

            if self.loopback_enable:
                for mac in self.port_mac:
                    if not mac.tx.empty():
                        await mac.rx.send(await mac.tx.recv())
                        await Timer(100, units="ns") 

    # async def send_pkts(self, pkts):
    #     for k, pkt_data in enumerate(pkts):
    #         qid = k % len(self.driver.interfaces[0].txq)
    #         rank = random.randint(0, 0xFFF)
    #         await self.driver.interfaces[0].start_xmit(pkt_data, qid, rank=rank)
    #         await RisingEdge(self.dut.clk)

    # async def recv_pkts(self, count):
    #     for _ in range(count):
    #         pkt = await self.driver.interfaces[0].recv()
    #         if self.driver.interfaces[0].if_feature_rx_csum:
    #             assert pkt.rx_checksum == ~scapy.utils.checksum(bytes(pkt.data[14:])) & 0xFFFF
    #         await RisingEdge(self.dut.clk)

    def _frame_to_bytes(self, x):
        """兼容 cocotbext-eth 可能返回的 bytes/bytearray/Frame(AxiStreamFrame) 等类型"""
        if isinstance(x, (bytes, bytearray)):
            return bytes(x)
        if hasattr(x, "data"):
            return bytes(x.data)
        return bytes(x)

    async def peer_stack(self, mac: EthMac, peer_mac: str, peer_ip: str):
        """
        cocotb 模拟线端对端：监听 DUT 发出的帧（mac.tx.recv），
        遇到 ARP who-has(peer_ip) 就回 ARP is-at，
        遇到 ICMP echo-request(dst=peer_ip) 就回 echo-reply。
        """
        try:
            while True:
                raw = await mac.tx.recv()
                pkt_bytes = self._frame_to_bytes(raw)

                eth = Ether(pkt_bytes)

                # 可选：调试用，建议先开一阵子
                # self.log.info("Peer RX: %s", eth.summary())

                # ---- ARP request -> ARP reply ----
                if eth.type == 0x0806 and eth.haslayer(ARP):
                    arp = eth[ARP]
                    # who-has peer_ip ?
                    if arp.op == 1 and arp.pdst == peer_ip:
                        rep = Ether(dst=eth.src, src=peer_mac) / ARP(
                            op=2,                 # is-at
                            hwsrc=peer_mac,
                            psrc=peer_ip,
                            hwdst=arp.hwsrc,
                            pdst=arp.psrc
                        )
                        # self.log.info("Peer TX: ARP reply (%s is-at %s)", peer_ip, peer_mac)
                        await mac.rx.send(bytes(rep))
                    continue

                # ---- ICMP echo request -> echo reply ----
                if eth.type == 0x0800 and eth.haslayer(IP) and eth.haslayer(ICMP):
                    ip = eth[IP]
                    icmp = eth[ICMP]

                    if ip.dst == peer_ip and icmp.type == 8:  # echo-request
                        payload = b""
                        if eth.haslayer(Raw):
                            payload = bytes(eth[Raw].load)

                        rep = (
                            Ether(dst=eth.src, src=peer_mac) /
                            IP(src=peer_ip, dst=ip.src) /
                            ICMP(type=0, id=icmp.id, seq=icmp.seq) /
                            Raw(load=payload)
                        )
                        # self.log.info("Peer TX: ICMP echo-reply seq=%d", icmp.seq)
                        await mac.rx.send(bytes(rep))
                    continue

        except Exception:
            self.log.exception("peer_stack crashed", exc_info=True)
            raise


# plt.rcParams['font.family'] = 'serif'
# plt.rcParams['font.serif'] = ['Times New Roman']

plt.rcParams['font.family'] = 'STIXGeneral'
plt.rcParams['font.size'] = 10.5

@cocotb.test()
async def run_test_nic(dut):

    tb = TB(dut, msix_count=2**len(dut.core_pcie_inst.irq_index), force_eth_speed=SCHED_TEST_LINK_SPEED)
    tb.log.info("irq_index: %d", len(dut.core_pcie_inst.irq_index))
    await tb.init()

    tb.log.info("Init driver")
    await tb.driver.init_pcie_dev(tb.rc.find_device(tb.dev.functions[0].pcie_id))
    for interface in tb.driver.interfaces:
        await interface.open()

    await tb.driver.hw_regs.read_dword(0)
    tb.log.info("Init complete")

    # Create standalone legend figure with pastel colors
    legend_configs = [
        {'qid': i, 'color': PASTEL_COLORS[i], 'name': f'Q{i}'}
        for i in range(10)
    ]
    create_legend_figure(legend_configs, prefix="pastel_legend")

    # await test_ping(tb,interface)
    await test_strict_priority(tb, interface)
    # await test_strict_priority_barrier(tb, interface)
    await test_wf2q(tb, interface)
    await test_edf(tb, interface)
    await test_sjf_srpt_approx(tb, interface)

    await RisingEdge(dut.clk)
    await RisingEdge(dut.clk)





plt.rcParams.update({
    # 'font.family': 'Arial',
    'font.size': 16,          # 基础字体大小（超大）
    'axes.titlesize': 20,     # 标题字体
    'axes.labelsize': 18,     # 轴标签字体
    'xtick.labelsize': 16,    # x轴刻度
    'ytick.labelsize': 16,    # y轴刻度
    'legend.fontsize': 16,    # 图例字体
    'figure.titlesize': 22,   # 总标题字体
})



async def test_ping(tb, interface):
       # ====== 配置：主机(host) 与 对端(peer) 的 IP/MAC ======
    host_ip  = "192.168.1.10"
    peer_ip  = "192.168.1.20"
    host_mac = "02:00:00:00:00:01"
    peer_mac = "02:00:00:00:00:02"

    # ====== 启动对端协议栈（每个 interface 对应一个线端 mac）======
    peer_tasks = []
    tb.log.info("Start peer stacks")
    for interface in tb.driver.interfaces:
        wire_mac = tb.port_mac[interface.index*interface.port_count]
        peer_tasks.append(cocotb.start_soon(tb.peer_stack(wire_mac, peer_mac=peer_mac, peer_ip=peer_ip)))

    # ====== 对每个 interface 做：ARP 一次 + ping N 次 ======
    ping_count = 10
    ping_id = 0x1234

    for interface in tb.driver.interfaces:
        tb.log.info("=== Interface %d ping test ===", interface.index)

        # ---------------- ARP request（只做一次） ----------------
        arp_req = Ether(dst="ff:ff:ff:ff:ff:ff", src=host_mac) / ARP(
            op=1,              # who-has
            hwsrc=host_mac,
            psrc=host_ip,
            hwdst="00:00:00:00:00:00",
            pdst=peer_ip
        )

        tb.log.info("Host: send ARP request for %s", peer_ip)
        await interface.start_xmit(bytes(arp_req), 0, rank=0x100)

        arp_reply_pkt = await interface.recv()
        arp_rep_eth = Ether(bytes(arp_reply_pkt.data))

        assert arp_rep_eth.type == 0x0806 and arp_rep_eth.haslayer(ARP), "Expected ARP reply"
        assert arp_rep_eth[ARP].op == 2, "Expected ARP is-at"
        assert arp_rep_eth[ARP].psrc == peer_ip and arp_rep_eth[ARP].pdst == host_ip, "ARP fields mismatch"

        learned_peer_mac = arp_rep_eth[ARP].hwsrc
        tb.log.info("Host: learned peer MAC %s", learned_peer_mac)

        # ---------------- 多次 ping ----------------
        for seq in range(ping_count):
            payload = f"ping-{seq}".encode()

            echo_req = (
                Ether(dst=learned_peer_mac, src=host_mac) /
                IP(src=host_ip, dst=peer_ip) /
                ICMP(type=8, id=ping_id, seq=seq) /
                Raw(load=payload)
            )

            tb.log.info("Host: send ICMP echo-request seq=%d", seq)
            await interface.start_xmit(bytes(echo_req), 0, rank=0x100)

            echo_reply_pkt = await interface.recv()
            rep = Ether(bytes(echo_reply_pkt.data))

            assert rep.type == 0x0800 and rep.haslayer(IP) and rep.haslayer(ICMP), "Expected IPv4+ICMP reply"
            assert rep[IP].src == peer_ip and rep[IP].dst == host_ip, "IP mismatch"
            assert rep[ICMP].type == 0 and rep[ICMP].id == ping_id and rep[ICMP].seq == seq, "ICMP mismatch"
            if rep.haslayer(Raw):
                assert bytes(rep[Raw].load) == payload, "Payload mismatch"

            # 可选：如果启用了 RX checksum offload，只对 IP 包校验（不要对 ARP 校验）
            if interface.if_feature_rx_csum:
                assert echo_reply_pkt.rx_checksum == ~scapy.utils.checksum(bytes(echo_reply_pkt.data[14:])) & 0xffff

            tb.log.info("Ping seq=%d OK", seq)

            await Timer(1, "us")

    # ====== 检查 peer task 有没有崩（避免后台悄悄炸了）======
    for t in peer_tasks:
        if t.done() and t.exception() is not None:
            raise t.exception()

    tb.log.info("All ping tests passed")

async def test_strict_priority(tb, interface):

    tb.log.info("=== Testing Strict Priority Scheduler ===")
    
    queue_configs = [
        {'qid': 0, 'rank': 0x100, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[0], 'name': 'Q0'},
        {'qid': 1, 'rank': 0x200, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[1], 'name': 'Q1'},
        {'qid': 2, 'rank': 0x300, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[2], 'name': 'Q2'},
        {'qid': 3, 'rank': 0x400, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[3], 'name': 'Q3'},
        {'qid': 4, 'rank': 0x500, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[4], 'name': 'Q4'},
        {'qid': 5, 'rank': 0x600, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[5], 'name': 'Q5'},
        {'qid': 6, 'rank': 0x700, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[6], 'name': 'Q6'},
        {'qid': 7, 'rank': 0x800, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[7], 'name': 'Q7'},
        {'qid': 8, 'rank': 0x900, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[8], 'name': 'Q8'},
        {'qid': 9, 'rank': 0x1000, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[9], 'name': 'Q9'},
    ]

    tb.log.info("Preparing packets...")
    pkts_per_queue = {
        cfg['qid']: [
            {'pkt': build_sched_test_pkt(cfg['qid'], seq), 'rank': cfg['rank'], 'seq': seq}
            for seq in range(cfg['count'])
        ]
        for cfg in queue_configs
    }

    tb.loopback_enable = True

    sent_counts = {cfg['qid']: 0 for cfg in queue_configs}
    producer_tasks = [
        cocotb.start_soon(send_queue_burst(tb, interface, cfg['qid'], pkts_per_queue[cfg['qid']], sent_counts))
        for cfg in queue_configs
    ]

    total_pkts = sum(cfg['count'] for cfg in queue_configs)
    await cocotb.triggers.with_timeout(Combine(*producer_tasks), WF2Q_SEND_TIMEOUT_US, 'us')

    # 接收
    tb.log.info("Receiving packets...")
    recv_data = []
    recv_seqs = {cfg['qid']: set() for cfg in queue_configs}
    expected_seqs = {cfg['qid']: set(range(cfg['count'])) for cfg in queue_configs}

    try:
        for pos in range(total_pkts):
            pkt = await cocotb.triggers.with_timeout(interface.recv(), WF2Q_RECV_TIMEOUT_US, 'us')
            qid = pkt.data[0]
            seq = int.from_bytes(pkt.data[1:5], 'little')
            recv_seqs[qid].add(seq)
            recv_data.append({'pos': pos, 'qid': qid, 'seq': seq})

            if pos < 10:
                tb.log.info(f"DEBUG: pos={pos}, qid={qid}, seq={seq}")
            if (pos + 1) % 25 == 0 or pos == 0:
                tb.log.info(f"SP progress: {pos+1}/{total_pkts} received")
                for cfg in queue_configs:
                    q = cfg['qid']
                    tb.log.info(f"  Q{q}: {len(recv_seqs[q])}/{cfg['count']}")

    except SimTimeoutError:
        tb.log.error(f"SP TIMEOUT at pos={len(recv_data)}, only received {len(recv_data)}/{total_pkts} packets")
        for cfg in queue_configs:
            qid = cfg['qid']
            missing = expected_seqs[qid] - recv_seqs[qid]
            tb.log.error(f"  Q{qid}: received {len(recv_seqs[qid])}/{cfg['count']}, missing seqs: {sorted(missing)[:20]}")
        raise
    except Exception as e:
        tb.log.error(f"Error receiving packet at position {len(recv_data)}: {e}")
        tb.log.error(f"Received {len(recv_data)} packets before error")
        raise

    tb.loopback_enable = False

    all_ok = True
    for cfg in queue_configs:
        qid = cfg['qid']
        missing = expected_seqs[qid] - recv_seqs[qid]
        if missing:
            all_ok = False
            tb.log.error(f"SP missing Q{qid}: {sorted(missing)[:10]}")

    create_sp_cumulative(recv_data, queue_configs, prefix="pastel_sp")
    assert all_ok, "Strict priority missing packets"
    tb.log.info("✓ Test completed with visualization")

async def test_strict_priority_barrier(tb, interface):

    tb.log.info("=== Testing Strict Priority Scheduler With TX Barrier ===")

    queue_configs = [
        {'qid': 0, 'rank': 0x100, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[0], 'name': 'Q0'},
        {'qid': 1, 'rank': 0x200, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[1], 'name': 'Q1'},
        {'qid': 2, 'rank': 0x300, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[2], 'name': 'Q2'},
        {'qid': 3, 'rank': 0x400, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[3], 'name': 'Q3'},
        {'qid': 4, 'rank': 0x500, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[4], 'name': 'Q4'},
        {'qid': 5, 'rank': 0x600, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[5], 'name': 'Q5'},
        {'qid': 6, 'rank': 0x700, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[6], 'name': 'Q6'},
        {'qid': 7, 'rank': 0x800, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[7], 'name': 'Q7'},
        {'qid': 8, 'rank': 0x900, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[8], 'name': 'Q8'},
        {'qid': 9, 'rank': 0x1000, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[9], 'name': 'Q9'},
    ]

    tb.log.info("Preparing packets for barrier test...")
    pkts_per_queue = {
        cfg['qid']: [
            {'pkt': build_sched_test_pkt(cfg['qid'], seq), 'rank': cfg['rank'], 'seq': seq}
            for seq in range(cfg['count'])
        ]
        for cfg in queue_configs
    }

    tb.loopback_enable = True
    set_interface_tx_pause(tb, interface, True)
    await Timer(2, 'us')

    sent_counts = {cfg['qid']: 0 for cfg in queue_configs}
    producer_tasks = [
        cocotb.start_soon(send_queue_burst(tb, interface, cfg['qid'], pkts_per_queue[cfg['qid']], sent_counts))
        for cfg in queue_configs
    ]

    total_pkts = sum(cfg['count'] for cfg in queue_configs)
    await cocotb.triggers.with_timeout(Combine(*producer_tasks), WF2Q_SEND_TIMEOUT_US, 'us')

    tb.log.info("Releasing TX barrier and starting receive phase...")
    set_interface_tx_pause(tb, interface, False)
    await Timer(2, 'us')

    recv_data = []
    recv_seqs = {cfg['qid']: set() for cfg in queue_configs}
    expected_seqs = {cfg['qid']: set(range(cfg['count'])) for cfg in queue_configs}

    try:
        for pos in range(total_pkts):
            pkt = await cocotb.triggers.with_timeout(interface.recv(), WF2Q_RECV_TIMEOUT_US, 'us')
            qid = pkt.data[0]
            seq = int.from_bytes(pkt.data[1:5], 'little')
            recv_seqs[qid].add(seq)
            recv_data.append({'pos': pos, 'qid': qid, 'seq': seq})

            if pos < 10:
                tb.log.info(f"SPB DEBUG: pos={pos}, qid={qid}, seq={seq}")
            if (pos + 1) % 25 == 0 or pos == 0:
                tb.log.info(f"SPB progress: {pos+1}/{total_pkts} received")
                for cfg in queue_configs:
                    q = cfg['qid']
                    tb.log.info(f"  Q{q}: {len(recv_seqs[q])}/{cfg['count']}")

    except SimTimeoutError:
        tb.log.error(f"SPB TIMEOUT at pos={len(recv_data)}, only received {len(recv_data)}/{total_pkts} packets")
        for cfg in queue_configs:
            qid = cfg['qid']
            missing = expected_seqs[qid] - recv_seqs[qid]
            tb.log.error(f"  Q{qid}: received {len(recv_seqs[qid])}/{cfg['count']}, missing seqs: {sorted(missing)[:20]}")
        raise
    finally:
        set_interface_tx_pause(tb, interface, False)

    tb.loopback_enable = False

    all_ok = True
    for cfg in queue_configs:
        qid = cfg['qid']
        missing = expected_seqs[qid] - recv_seqs[qid]
        if missing:
            all_ok = False
            tb.log.error(f"SPB missing Q{qid}: {sorted(missing)[:10]}")

    create_sp_cumulative(recv_data, queue_configs, prefix="pastel_sp_barrier")
    assert all_ok, "Strict priority barrier missing packets"
    tb.log.info("✓ Strict priority barrier test completed")


def create_sp_cumulative(recv_data, queue_configs, prefix="sp_cumulative", export_excel=True):
    """
    绘制严格优先级调度下的累积接收曲线及理论分界线（字体调大版）。
    可选择将累积数据导出到Excel文件。

    参数:
        recv_data: 数据包列表，每个包含 'qid', 'pos'
        queue_configs: 队列配置，每个含 'qid', 'rank', 'color', 'name', 'count'
        prefix: 输出文件前缀
        export_excel: 是否导出Excel数据文件（默认True）
    """
    # 按优先级排序（rank升序，高优先级在前）
    sorted_cfg = sorted(queue_configs, key=lambda x: x['rank'])

    # 确定x轴范围
    max_pos = max(pkt['pos'] for pkt in recv_data) if recv_data else 0

    # 创建画布
    fig, ax = plt.subplots(figsize=(11, 6.5))

    # 标题字体
    ax.set_title('Cumulative Packet Count (Strict Priority)',
                 fontsize=16, fontweight='bold')

    # 存储每个队列的累积数据（用于导出）
    cum_data = {}

    # 绘制每个队列的累积曲线
    for cfg in sorted_cfg:
        qid = cfg['qid']
        positions = sorted([pkt['pos'] for pkt in recv_data if pkt['qid'] == qid])
        if positions:
            cum_counts = list(range(1, len(positions) + 1))
            ax.plot(positions, cum_counts,
                    color=cfg['color'],
                    linewidth=2.5,
                    label=f"{cfg['name']} (Rank=0x{cfg['rank']:X})")
            cum_data[cfg['name']] = {'positions': positions, 'counts': cum_counts}
        else:
            cum_data[cfg['name']] = {'positions': [], 'counts': []}

    # 绘制理论分界线
    # boundary = 0
    # for cfg in sorted_cfg[:-1]:
    #     boundary += cfg['count']
    #     ax.axvline(boundary, color='gray', linestyle='--', linewidth=1.5, alpha=0.7)
    #     ax.text(boundary, ax.get_ylim()[1] * 0.9,
    #             f"{cfg['name']} done",
    #             rotation=90, fontsize=11, ha='right', va='top')

    # 坐标轴标签字体
    ax.set_xlabel("Reception Position", fontsize=14)
    ax.set_ylabel("Cumulative Packet Count", fontsize=14)
    ax.set_xlim(0, max_pos + 10)

    # 刻度字体
    ax.tick_params(axis='both', labelsize=12)

    ax.grid(True, alpha=0.3)

    plt.tight_layout()
    plt.savefig(f"{prefix}.png", dpi=300, bbox_inches="tight")
    plt.savefig(f"{prefix}.pdf", bbox_inches="tight")
    print(f"\n✓ Saved: {prefix}.png / {prefix}.pdf\n")

    # ========== Excel导出部分 ==========
    if export_excel:
        try:
            excel_file = f"{prefix}_data.xlsx"
            with pd.ExcelWriter(excel_file, engine='openpyxl') as writer:
                # 1. 每个队列的累积数据写入单独sheet
                for cfg in sorted_cfg:
                    name = cfg['name']
                    data = cum_data[name]
                    if data['positions']:
                        df = pd.DataFrame({
                            'Position': data['positions'],
                            'Cumulative Count': data['counts']
                        })
                    else:
                        df = pd.DataFrame({'Position': [], 'Cumulative Count': []})
                    # sheet名称不能超过31字符，且不能有特殊字符
                    sheet_name = name[:20].replace('/', '_').replace('\\', '_')
                    df.to_excel(writer, sheet_name=sheet_name, index=False)

                # 2. 摘要sheet
                summary = []
                cumulative_boundary = 0
                for i, cfg in enumerate(sorted_cfg):
                    name = cfg['name']
                    data = cum_data[name]
                    actual_count = len(data['positions'])
                    avg_pos = np.mean(data['positions']) if actual_count > 0 else 0
                    last_pos = data['positions'][-1] if actual_count > 0 else 0

                    # 理论边界：所有更高优先级队列的包数之和（rank升序累积）
                    # 当前队列的理论边界 = 前i个队列的count之和（因为rank最小的是最高优先级）
                    theoretical_boundary = cumulative_boundary + cfg['count']
                    # 偏差：实际最后位置与理论边界的差值（正表示延迟）
                    pos_deviation = last_pos - theoretical_boundary if actual_count > 0 else 0

                    summary.append({
                        'Queue': name,
                        'Rank (hex)': f"0x{cfg['rank']:X}",
                        'Actual Packets': actual_count,
                        'Theoretical End Boundary': theoretical_boundary,
                        'Actual Last Position': last_pos,
                        'Avg Position': round(avg_pos, 2),
                        'Position Deviation (Last - Bound)': round(pos_deviation, 2)
                    })

                    cumulative_boundary += cfg['count']

                df_summary = pd.DataFrame(summary)
                df_summary.to_excel(writer, sheet_name='Summary', index=False)

            print(f"✓ Exported data to: {excel_file}")
        except ImportError:
            print("⚠ pandas or openpyxl not installed. Skipping Excel export.")
        except Exception as e:
            print(f"⚠ Failed to export Excel: {e}")

    plt.show()

async def test_edf(tb, interface):
    tb.log.info("=== Testing EDF Scheduler ===")

    queue_configs = [
        {'qid': 0, 'base_deadline': 1000, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[0], 'name': 'Q0'},
        {'qid': 1, 'base_deadline': 1600, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[1], 'name': 'Q1'},
        {'qid': 2, 'base_deadline': 2200, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[2], 'name': 'Q2'},
        {'qid': 3, 'base_deadline': 2800, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[3], 'name': 'Q3'},
        {'qid': 4, 'base_deadline': 3400, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[4], 'name': 'Q4'},
        {'qid': 5, 'base_deadline': 4000, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[5], 'name': 'Q5'},
        {'qid': 6, 'base_deadline': 4600, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[6], 'name': 'Q6'},
        {'qid': 7, 'base_deadline': 5200, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[7], 'name': 'Q7'},
        {'qid': 8, 'base_deadline': 5800, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[8], 'name': 'Q8'},
        {'qid': 9, 'base_deadline': 6400, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[9], 'name': 'Q9'},
    ]

    rank_max = 0x1FFF
    deadline_step = 11
    metric_lookup = {}
    pkts_by_qid = {cfg['qid']: [] for cfg in queue_configs}

    for cfg in queue_configs:
        qid = cfg['qid']
        for seq in range(cfg['count']):
            deadline = cfg['base_deadline'] + seq * deadline_step
            rank = min(deadline, rank_max)
            pkt = build_sched_test_pkt(qid, seq)
            metric_lookup[(qid, seq)] = rank
            pkts_by_qid[qid].append({
                'pkt': pkt,
                'rank': rank,
                'seq': seq,
                'deadline': deadline,
            })

    tb.loopback_enable = True
    await Timer(10, 'us')

    sent_counts = {cfg['qid']: 0 for cfg in queue_configs}
    producer_tasks = [
        cocotb.start_soon(send_queue_burst(tb, interface, cfg['qid'], pkts_by_qid[cfg['qid']], sent_counts, label="EDF"))
        for cfg in queue_configs
    ]

    total_pkts = sum(cfg['count'] for cfg in queue_configs)
    try:
        await cocotb.triggers.with_timeout(Combine(*producer_tasks), WF2Q_SEND_TIMEOUT_US, 'us')
    except SimTimeoutError:
        tb.log.error("EDF send stage timeout after %d us", WF2Q_SEND_TIMEOUT_US)
        for cfg in queue_configs:
            qid = cfg['qid']
            tb.log.error("  Q%d send progress: %d/%d", qid, sent_counts[qid], cfg['count'])
        raise

    recv_data, recv_seqs, expected_seqs, all_ok = await receive_scheduler_packets(tb, interface, queue_configs, total_pkts, label="EDF")
    tb.loopback_enable = False

    monotonic_violations = []
    prev_rank = None
    for pkt in recv_data:
        rank = metric_lookup[(pkt['qid'], pkt['seq'])]
        if prev_rank is not None and rank < prev_rank:
            monotonic_violations.append((pkt['pos'], prev_rank, rank, pkt['qid'], pkt['seq']))
        prev_rank = rank

    for violation in monotonic_violations[:10]:
        pos, prev_rank, rank, qid, seq = violation
        tb.log.warning(
            "EDF order violation at pos=%d: prev_rank=%d, current_rank=%d (Q%d seq=%d)",
            pos, prev_rank, rank, qid, seq
        )

    if monotonic_violations:
        tb.log.warning("EDF rank ordering violated %d times during startup/online scheduling", len(monotonic_violations))

    create_metric_scatter(
        recv_data,
        metric_lookup,
        queue_configs,
        prefix="pastel_edf",
        title="EDF Scheduling Result",
        ylabel="Deadline Rank",
    )

    assert all_ok, "EDF missing packets"
    tb.log.info("✓ EDF test completed")


async def test_sjf_srpt_approx(tb, interface):
    tb.log.info("=== Testing SJF/SRPT-Approx Scheduler ===")

    queue_configs = [
        {'qid': 0, 'pkt_size': 256, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[0], 'name': 'Q0'},
        {'qid': 1, 'pkt_size': 384, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[1], 'name': 'Q1'},
        {'qid': 2, 'pkt_size': 512, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[2], 'name': 'Q2'},
        {'qid': 3, 'pkt_size': 768, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[3], 'name': 'Q3'},
        {'qid': 4, 'pkt_size': 1024, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[4], 'name': 'Q4'},
        {'qid': 5, 'pkt_size': 1280, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[5], 'name': 'Q5'},
        {'qid': 6, 'pkt_size': 1536, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[6], 'name': 'Q6'},
        {'qid': 7, 'pkt_size': 2048, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[7], 'name': 'Q7'},
        {'qid': 8, 'pkt_size': 3072, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[8], 'name': 'Q8'},
        {'qid': 9, 'pkt_size': 4096, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[9], 'name': 'Q9'},
    ]

    rank_max = 0x1FFF
    metric_lookup = {}
    completion_pos = {cfg['qid']: [] for cfg in queue_configs}
    pkts_by_qid = {cfg['qid']: [] for cfg in queue_configs}

    raw_entries = []
    raw_remaining_values = []

    for cfg in queue_configs:
        qid = cfg['qid']
        pkt_size = cfg['pkt_size']
        remaining_bytes = pkt_size * cfg['count']
        for seq in range(cfg['count']):
            raw_entries.append({
                'qid': qid,
                'seq': seq,
                'pkt_size': pkt_size,
                'remaining_bytes': remaining_bytes,
            })
            raw_remaining_values.append(remaining_bytes)
            remaining_bytes -= pkt_size

    min_remaining = min(raw_remaining_values)
    max_remaining = max(raw_remaining_values)

    def normalize_remaining_to_rank(value):
        if max_remaining == min_remaining:
            return 1
        scaled = 1 + int((value - min_remaining) * (rank_max - 1) / (max_remaining - min_remaining))
        return min(max(scaled, 1), rank_max)

    for entry in raw_entries:
        qid = entry['qid']
        seq = entry['seq']
        pkt_size = entry['pkt_size']
        remaining_bytes = entry['remaining_bytes']
        rank = normalize_remaining_to_rank(remaining_bytes)
        pkt = build_sched_test_pkt(qid, seq, size=pkt_size)
        metric_lookup[(qid, seq)] = rank
        pkts_by_qid[qid].append({
            'pkt': pkt,
            'rank': rank,
            'seq': seq,
            'remaining_bytes': remaining_bytes,
        })

    tb.loopback_enable = True
    await Timer(10, 'us')

    sent_counts = {cfg['qid']: 0 for cfg in queue_configs}
    producer_tasks = [
        cocotb.start_soon(send_queue_burst(tb, interface, cfg['qid'], pkts_by_qid[cfg['qid']], sent_counts, label="SRPT"))
        for cfg in queue_configs
    ]

    total_pkts = sum(cfg['count'] for cfg in queue_configs)
    try:
        await cocotb.triggers.with_timeout(Combine(*producer_tasks), WF2Q_SEND_TIMEOUT_US, 'us')
    except SimTimeoutError:
        tb.log.error("SRPT send stage timeout after %d us", WF2Q_SEND_TIMEOUT_US)
        for cfg in queue_configs:
            qid = cfg['qid']
            tb.log.error("  Q%d send progress: %d/%d", qid, sent_counts[qid], cfg['count'])
        raise

    recv_data, recv_seqs, expected_seqs, all_ok = await receive_scheduler_packets(tb, interface, queue_configs, total_pkts, label="SRPT")
    tb.loopback_enable = False

    for pkt in recv_data:
        completion_pos[pkt['qid']].append(pkt['pos'])

    queue_finish_order = []
    for cfg in queue_configs:
        qid = cfg['qid']
        if completion_pos[qid]:
            queue_finish_order.append((max(completion_pos[qid]), qid, cfg['pkt_size']))

    queue_finish_order.sort()
    finish_violations = []
    prev_size = None
    for finish_pos, qid, pkt_size in queue_finish_order:
        if prev_size is not None and pkt_size < prev_size:
            finish_violations.append((finish_pos, qid, pkt_size, prev_size))
        prev_size = pkt_size

    for finish_pos, qid, pkt_size, prev_size in finish_violations[:10]:
        tb.log.error(
            "SRPT finish-order violation at pos=%d: Q%d size=%d finished after larger size=%d",
            finish_pos, qid, pkt_size, prev_size
        )

    create_metric_scatter(
        recv_data,
        metric_lookup,
        queue_configs,
        prefix="pastel_sjf_srpt",
        title="SJF/SRPT-Approx Scheduling Result",
        ylabel="Approx Remaining Bytes Rank",
    )

    assert all_ok, "SJF/SRPT-approx missing packets"
    assert not finish_violations, f"SJF/SRPT-approx finish ordering violated {len(finish_violations)} times"
    tb.log.info("✓ SJF/SRPT-approx test completed")


async def test_wf2q(tb, interface):
    tb.log.info("=== Testing WF2Q Scheduler ===")
    
    queue_configs = [
        {'qid': 0, 'weight': 8, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[0], 'name': 'Q0'},
        {'qid': 1, 'weight': 7, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[1], 'name': 'Q1'},
        {'qid': 2, 'weight': 6, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[2], 'name': 'Q2'},
        {'qid': 3, 'weight': 5, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[3], 'name': 'Q3'},
        {'qid': 4, 'weight': 4, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[4], 'name': 'Q4'},
        {'qid': 5, 'weight': 3, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[5], 'name': 'Q5'},
        {'qid': 6, 'weight': 2, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[6], 'name': 'Q6'},
        {'qid': 7, 'weight': 2, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[7], 'name': 'Q7'},
        {'qid': 8, 'weight': 1, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[8], 'name': 'Q8'},
        {'qid': 9, 'weight': 1, 'count': SCHED_TEST_PKT_COUNT, 'color': PASTEL_COLORS[9], 'name': 'Q9'},
    ]

    weight_map = {cfg['qid']: cfg['weight'] for cfg in queue_configs}
    rank_max = 0x1FFF

    virtual_finish_times = {cfg['qid']: 0.0 for cfg in queue_configs}
    pkt_entries = []

    for cfg in queue_configs:
        qid = cfg['qid']
        weight = cfg['weight']
        increment = 1.0 / weight

        for seq in range(cfg['count']):
            vft_current = virtual_finish_times[qid] + increment
            virtual_finish_times[qid] = vft_current
            pkt = build_sched_test_pkt(qid, seq)
            pkt_entries.append({
                'pkt': pkt,
                'qid': qid,
                'seq': seq,
                'weight': weight,
                'vft': vft_current,
            })

    ordered_entries = sorted(pkt_entries, key=lambda p: (p['vft'], p['qid'], p['seq']))
    assert len(ordered_entries) <= rank_max, "WFQ test generates more packets than available rank space"

    for rank, entry in enumerate(ordered_entries, start=1):
        entry['rank'] = rank

    pkts_with_rank = sorted(pkt_entries, key=lambda p: (p['qid'], p['seq']))

    tb.loopback_enable = True
    await Timer(10, 'us')

    tb.log.info("Sending packets with concurrent queue producers...")
    pkts_by_qid = {cfg['qid']: [] for cfg in queue_configs}
    for p in pkts_with_rank:
        pkts_by_qid[p['qid']].append(p)

    sent_counts = {cfg['qid']: 0 for cfg in queue_configs}
    producer_tasks = [
        cocotb.start_soon(send_queue_burst(tb, interface, cfg['qid'], pkts_by_qid[cfg['qid']], sent_counts))
        for cfg in queue_configs
    ]

    total_pkts = len(pkts_with_rank)

    try:
        await cocotb.triggers.with_timeout(Combine(*producer_tasks), WF2Q_SEND_TIMEOUT_US, 'us')
    except SimTimeoutError:
        tb.log.error("WF2Q send stage timeout after %d us", WF2Q_SEND_TIMEOUT_US)
        for cfg in queue_configs:
            qid = cfg['qid']
            tb.log.error("  Q%d send progress: %d/%d", qid, sent_counts[qid], cfg['count'])
        raise

    tb.log.info(f"Sent {total_pkts} packets total, now receiving...")

    # ── 接收：带序号检测、超时保护、丢包诊断 ──
    recv_data = []
    
    # 追踪每个队列已收到的序号
    recv_seqs = {cfg['qid']: set() for cfg in queue_configs}
    expected_seqs = {cfg['qid']: set(range(cfg['count'])) for cfg in queue_configs}

    TIMEOUT_US = WF2Q_RECV_TIMEOUT_US

    for pos in range(total_pkts):
        # 超时接收
        try:
            recv_coro = interface.recv()
            pkt = await cocotb.triggers.with_timeout(
                recv_coro, TIMEOUT_US, 'us'
            )
        except SimTimeoutError:
            tb.log.error(f"TIMEOUT at pos={pos}, only received {len(recv_data)}/{total_pkts} packets")
            
            # 诊断：打印每个队列的收包情况
            tb.log.error("=== RECEIVE DIAGNOSIS ===")
            for cfg in queue_configs:
                qid = cfg['qid']
                got = recv_seqs[qid]
                missing = expected_seqs[qid] - got
                tb.log.error(
                    f"  Q{qid}: received {len(got)}/{cfg['count']}, "
                    f"missing seqs: {sorted(missing)[:20]}"  # 最多打印前20个缺失序号
                )
            break

        # 解析包
        raw_qid = pkt.data[0]
        raw_seq = int.from_bytes(pkt.data[1:5], 'little')

        # 基础合法性检查
        if raw_qid >= len(queue_configs):
            tb.log.warning(f"pos={pos}: INVALID qid={raw_qid}, raw bytes={list(pkt.data[:8])}")
            recv_data.append({'pos': pos, 'qid': raw_qid, 'seq': raw_seq, 'valid': False})
            continue

        # 重复包检测
        if raw_seq in recv_seqs[raw_qid]:
            tb.log.warning(f"pos={pos}: DUPLICATE Q{raw_qid} seq={raw_seq}")
        
        # 超出预期范围的序号
        if raw_seq >= queue_configs[raw_qid]['count']:
            tb.log.warning(
                f"pos={pos}: OUT-OF-RANGE Q{raw_qid} seq={raw_seq} "
                f"(expected 0~{queue_configs[raw_qid]['count']-1})"
            )

        recv_seqs[raw_qid].add(raw_seq)
        recv_data.append({'pos': pos, 'qid': raw_qid, 'seq': raw_seq, 'valid': True})

        # 每收到 25 包打印一次进度，方便定位卡点
        if (pos + 1) % 25 == 0 or pos == 0:
            tb.log.info(f"Progress: {pos+1}/{total_pkts} received")
            for cfg in queue_configs:
                qid = cfg['qid']
                tb.log.info(f"  Q{qid}: {len(recv_seqs[qid])}/{cfg['count']}")

    tb.loopback_enable = False

    # ── 最终收包统计 ──
    tb.log.info("\n=== FINAL RECEIVE SUMMARY ===")
    all_ok = True
    for cfg in queue_configs:
        qid = cfg['qid']
        got = recv_seqs[qid]
        missing = expected_seqs[qid] - got
        status = "✓" if not missing else "✗"
        tb.log.info(
            f"  {status} Q{qid} (w={cfg['weight']}): "
            f"received {len(got)}/{cfg['count']}"
            + (f", MISSING: {sorted(missing)[:10]}" if missing else "")
        )
        if missing:
            all_ok = False

    if all_ok:
        tb.log.info("✓ All packets received correctly")
    else:
        tb.log.error("✗ Some packets missing — check hardware loopback path")

    # 前50包
    tb.log.info("\n=== First 50 packets RECEIVED ===")
    for i in range(min(50, len(recv_data))):
        p = recv_data[i]
        tb.log.info(
            f"Position {i:3d}: Q{p['qid']} seq={p['seq']:3d} weight={weight_map.get(p['qid'], '?')}"
        )

    if recv_data:
        # analyze_wf2q_fairness(recv_data, queue_configs)
        create_wf2q_cumulative(recv_data, queue_configs, prefix="pastel_wf2q")

    assert all_ok, "WF2Q missing packets"
    tb.log.info("✓ WF2Q test completed")

def create_wf2q_cumulative(recv_data, queue_configs, prefix="wf2q_cumulative", export_excel=True):
    """Plot WFQ cumulative service with ideal weighted reference lines."""
    sorted_cfg = sorted(queue_configs, key=lambda x: x['weight'], reverse=True)

    total_weight = sum(cfg['weight'] for cfg in queue_configs)
    total_pkts = len(recv_data)
    max_pos = max(pkt['pos'] for pkt in recv_data) if recv_data else 0

    fig, ax = plt.subplots(figsize=(12, 8.5))
    ax.set_title('WFQ Scheduling Result', fontsize=18, fontweight='bold')

    cum_data = {}

    for cfg in sorted_cfg:
        qid = cfg['qid']
        positions = np.array(sorted(pkt['pos'] for pkt in recv_data if pkt['qid'] == qid), dtype=float)
        if len(positions) == 0:
            cum_data[cfg['name']] = {'positions': [], 'counts': []}
            continue

        counts = np.arange(1, len(positions) + 1, dtype=float)
        ideal_counts = (positions + 1.0) * cfg['weight'] / total_weight

        ax.step(
            positions, counts, where='post', color=cfg['color'], linewidth=2.5,
            label=f"{cfg['name']} (W={cfg['weight']})"
        )
        ax.plot(
            positions, ideal_counts, color=cfg['color'], linewidth=1.2,
            linestyle=(0, (2, 2)), alpha=0.45
        )

        cum_data[cfg['name']] = {
            'positions': positions.tolist(),
            'counts': counts.tolist(),
        }

    ax.set_xlabel('Reception Position', fontsize=13)
    ax.set_ylabel('Cumulative Packet Count', fontsize=13)
    ax.set_xlim(0, max_pos + 10)
    ax.set_ylim(bottom=0)
    ax.grid(True, alpha=0.22, linewidth=0.8)
    ax.spines['top'].set_visible(False)
    ax.spines['right'].set_visible(False)
    ax.tick_params(axis='both', labelsize=11)

    fig.subplots_adjust(top=0.92, left=0.08, right=0.98, bottom=0.10)
    plt.savefig(f"{prefix}.png", dpi=300, bbox_inches="tight")
    plt.savefig(f"{prefix}.pdf", bbox_inches="tight")
    print(f"\n✓ Saved: {prefix}.png / {prefix}.pdf\n")

    if export_excel:
        try:
            excel_file = f"{prefix}_data.xlsx"
            with pd.ExcelWriter(excel_file, engine='openpyxl') as writer:
                for cfg in sorted_cfg:
                    name = cfg['name']
                    data = cum_data[name]
                    if data['positions']:
                        df = pd.DataFrame({
                            'Position': data['positions'],
                            'Cumulative Count': data['counts'],
                        })
                    else:
                        df = pd.DataFrame({'Position': [], 'Cumulative Count': []})
                    sheet_name = name[:20].replace('/', '_').replace('\\', '_')
                    df.to_excel(writer, sheet_name=sheet_name, index=False)

                summary = []
                for cfg in sorted_cfg:
                    name = cfg['name']
                    actual_count = len(cum_data[name]['positions'])
                    expected_count = total_pkts * cfg['weight'] / total_weight
                    avg_pos = np.mean(cum_data[name]['positions']) if actual_count > 0 else 0
                    deviation = abs(actual_count - expected_count) / expected_count * 100 if expected_count > 0 else 0
                    summary.append({
                        'Queue': name,
                        'Weight': cfg['weight'],
                        'Actual Packets': actual_count,
                        'Expected Packets (Ideal)': round(expected_count, 2),
                        'Avg Position': round(avg_pos, 2),
                        'Deviation %': round(deviation, 2)
                    })
                pd.DataFrame(summary).to_excel(writer, sheet_name='Summary', index=False)

            print(f"✓ Exported data to: {excel_file}")
        except ImportError:
            print("⚠ pandas or openpyxl not installed. Skipping Excel export.")
        except Exception as e:
            print(f"⚠ Failed to export Excel: {e}")

    plt.show()

# cocotb-test

tests_dir = os.path.dirname(__file__)
rtl_dir = os.path.abspath(os.path.join(tests_dir, '..', '..', 'rtl'))
lib_dir = os.path.abspath(os.path.join(rtl_dir, '..', 'lib'))
axi_rtl_dir = os.path.abspath(os.path.join(lib_dir, 'axi', 'rtl'))
axis_rtl_dir = os.path.abspath(os.path.join(lib_dir, 'axis', 'rtl'))
eth_rtl_dir = os.path.abspath(os.path.join(lib_dir, 'eth', 'rtl'))
pcie_rtl_dir = os.path.abspath(os.path.join(lib_dir, 'pcie', 'rtl'))


@pytest.mark.parametrize(("if_count", "ports_per_if", "axis_pcie_data_width",
        "axis_eth_data_width", "axis_eth_sync_data_width", "ptp_ts_enable"), [
            (1, 1, 256, 64, 64, 1),
            (1, 1, 256, 64, 64, 0),
            (2, 1, 256, 64, 64, 1),
            (1, 2, 256, 64, 64, 1),
            (1, 1, 256, 64, 128, 1),
            (1, 1, 512, 64, 64, 1),
            (1, 1, 512, 64, 128, 1),
            (1, 1, 512, 512, 512, 1),
        ])
def test_mqnic_core_pcie_us(request, if_count, ports_per_if, axis_pcie_data_width,
        axis_eth_data_width, axis_eth_sync_data_width, ptp_ts_enable):
    dut = "mqnic_core_pcie_us"
    module = os.path.splitext(os.path.basename(__file__))[0]
    toplevel = dut

    verilog_sources = [
        os.path.join(rtl_dir, f"{dut}.v"),
        os.path.join(rtl_dir, "mqnic_core_pcie.v"),
        os.path.join(rtl_dir, "mqnic_core.v"),
        os.path.join(rtl_dir, "mqnic_dram_if.v"),
        os.path.join(rtl_dir, "mqnic_interface_change.v"),
        os.path.join(rtl_dir, "mqnic_interface_tx.v"),
        os.path.join(rtl_dir, "mqnic_interface_rx.v"),
        os.path.join(rtl_dir, "mqnic_port.v"),
        os.path.join(rtl_dir, "mqnic_port_tx.v"),
        os.path.join(rtl_dir, "mqnic_port_rx.v"),
        os.path.join(rtl_dir, "mqnic_egress.v"),
        os.path.join(rtl_dir, "mqnic_ingress.v"),
        os.path.join(rtl_dir, "mqnic_l2_egress.v"),
        os.path.join(rtl_dir, "mqnic_l2_ingress.v"),
        os.path.join(rtl_dir, "mqnic_rx_queue_map.v"),
        os.path.join(rtl_dir, "mqnic_ptp.v"),
        os.path.join(rtl_dir, "mqnic_ptp_clock.v"),
        os.path.join(rtl_dir, "mqnic_ptp_perout.v"),
        os.path.join(rtl_dir, "mqnic_rb_clk_info.v"),
        os.path.join(rtl_dir, "cpl_write.v"),
        os.path.join(rtl_dir, "cpl_op_mux.v"),
        os.path.join(rtl_dir, "desc_fetch.v"),
        os.path.join(rtl_dir, "desc_op_mux.v"),
        os.path.join(rtl_dir, "queue_manager.v"),
        os.path.join(rtl_dir, "cpl_queue_manager.v"),
        os.path.join(rtl_dir, "tx_fifo.v"),
        os.path.join(rtl_dir, "rx_fifo.v"),
        os.path.join(rtl_dir, "tx_req_mux.v"),
        os.path.join(rtl_dir, "tx_engine.v"),
        os.path.join(rtl_dir, "rx_engine.v"),
        os.path.join(rtl_dir, "tx_checksum.v"),
        os.path.join(rtl_dir, "rx_hash.v"),
        os.path.join(rtl_dir, "rx_checksum.v"),
        os.path.join(rtl_dir, "stats_counter.v"),
        os.path.join(rtl_dir, "stats_collect.v"),
        os.path.join(rtl_dir, "stats_pcie_if.v"),
        os.path.join(rtl_dir, "stats_pcie_tlp.v"),
        os.path.join(rtl_dir, "stats_dma_if_pcie.v"),
        os.path.join(rtl_dir, "stats_dma_latency.v"),
        os.path.join(rtl_dir, "mqnic_tx_scheduler_block_rr.v"),
        os.path.join(rtl_dir, "tx_scheduler_rr.v"),
        os.path.join(eth_rtl_dir, "mac_ctrl_rx.v"),
        os.path.join(eth_rtl_dir, "mac_ctrl_tx.v"),
        os.path.join(eth_rtl_dir, "mac_pause_ctrl_rx.v"),
        os.path.join(eth_rtl_dir, "mac_pause_ctrl_tx.v"),
        os.path.join(eth_rtl_dir, "ptp_td_phc.v"),
        os.path.join(eth_rtl_dir, "ptp_td_leaf.v"),
        os.path.join(eth_rtl_dir, "ptp_perout.v"),
        os.path.join(axi_rtl_dir, "axil_crossbar.v"),
        os.path.join(axi_rtl_dir, "axil_crossbar_addr.v"),
        os.path.join(axi_rtl_dir, "axil_crossbar_rd.v"),
        os.path.join(axi_rtl_dir, "axil_crossbar_wr.v"),
        os.path.join(axi_rtl_dir, "axil_reg_if.v"),
        os.path.join(axi_rtl_dir, "axil_reg_if_rd.v"),
        os.path.join(axi_rtl_dir, "axil_reg_if_wr.v"),
        os.path.join(axi_rtl_dir, "axil_register_rd.v"),
        os.path.join(axi_rtl_dir, "axil_register_wr.v"),
        os.path.join(axi_rtl_dir, "arbiter.v"),
        os.path.join(axi_rtl_dir, "priority_encoder.v"),
        os.path.join(axis_rtl_dir, "axis_adapter.v"),
        os.path.join(axis_rtl_dir, "axis_arb_mux.v"),
        os.path.join(axis_rtl_dir, "axis_async_fifo.v"),
        os.path.join(axis_rtl_dir, "axis_async_fifo_adapter.v"),
        os.path.join(axis_rtl_dir, "axis_demux.v"),
        os.path.join(axis_rtl_dir, "axis_fifo.v"),
        os.path.join(axis_rtl_dir, "axis_fifo_adapter.v"),
        os.path.join(axis_rtl_dir, "axis_pipeline_fifo.v"),
        os.path.join(axis_rtl_dir, "axis_register.v"),
        os.path.join(pcie_rtl_dir, "pcie_axil_master.v"),
        os.path.join(pcie_rtl_dir, "pcie_tlp_demux.v"),
        os.path.join(pcie_rtl_dir, "pcie_tlp_demux_bar.v"),
        os.path.join(pcie_rtl_dir, "pcie_tlp_mux.v"),
        os.path.join(pcie_rtl_dir, "pcie_tlp_fifo.v"),
        os.path.join(pcie_rtl_dir, "pcie_tlp_fifo_raw.v"),
        os.path.join(pcie_rtl_dir, "pcie_msix.v"),
        os.path.join(pcie_rtl_dir, "irq_rate_limit.v"),
        os.path.join(pcie_rtl_dir, "dma_if_pcie.v"),
        os.path.join(pcie_rtl_dir, "dma_if_pcie_rd.v"),
        os.path.join(pcie_rtl_dir, "dma_if_pcie_wr.v"),
        os.path.join(pcie_rtl_dir, "dma_if_mux.v"),
        os.path.join(pcie_rtl_dir, "dma_if_mux_rd.v"),
        os.path.join(pcie_rtl_dir, "dma_if_mux_wr.v"),
        os.path.join(pcie_rtl_dir, "dma_if_desc_mux.v"),
        os.path.join(pcie_rtl_dir, "dma_ram_demux_rd.v"),
        os.path.join(pcie_rtl_dir, "dma_ram_demux_wr.v"),
        os.path.join(pcie_rtl_dir, "dma_psdpram.v"),
        os.path.join(pcie_rtl_dir, "dma_client_axis_sink.v"),
        os.path.join(pcie_rtl_dir, "dma_client_axis_source.v"),
        os.path.join(pcie_rtl_dir, "pcie_us_if.v"),
        os.path.join(pcie_rtl_dir, "pcie_us_if_rc.v"),
        os.path.join(pcie_rtl_dir, "pcie_us_if_rq.v"),
        os.path.join(pcie_rtl_dir, "pcie_us_if_cc.v"),
        os.path.join(pcie_rtl_dir, "pcie_us_if_cq.v"),
        os.path.join(pcie_rtl_dir, "pcie_us_cfg.v"),
        os.path.join(pcie_rtl_dir, "pulse_merge.v"),
    ]

    parameters = {}

    # Structural configuration
    parameters['IF_COUNT'] = if_count
    parameters['PORTS_PER_IF'] = ports_per_if
    parameters['SCHED_PER_IF'] = ports_per_if

    # Clock configuration
    parameters['CLK_PERIOD_NS_NUM'] = 4
    parameters['CLK_PERIOD_NS_DENOM'] = 1

    # PTP configuration
    parameters['PTP_CLK_PERIOD_NS_NUM'] = 32
    parameters['PTP_CLK_PERIOD_NS_DENOM'] = 5
    parameters['PTP_CLOCK_PIPELINE'] = 0
    parameters['PTP_CLOCK_CDC_PIPELINE'] = 0
    parameters['PTP_SEPARATE_TX_CLOCK'] = 0
    parameters['PTP_SEPARATE_RX_CLOCK'] = 0
    parameters['PTP_PORT_CDC_PIPELINE'] = 0
    parameters['PTP_PEROUT_ENABLE'] = 0
    parameters['PTP_PEROUT_COUNT'] = 1

    # Queue manager configuration
    parameters['EVENT_QUEUE_OP_TABLE_SIZE'] = 1024 #change
    parameters['TX_QUEUE_OP_TABLE_SIZE'] = 1024 #change
    parameters['RX_QUEUE_OP_TABLE_SIZE'] = 1024 #change
    parameters['CQ_OP_TABLE_SIZE'] = 1024 #change
    parameters['EQN_WIDTH'] = 6
    parameters['TX_QUEUE_INDEX_WIDTH'] = 8
    parameters['RX_QUEUE_INDEX_WIDTH'] = 8
    parameters['CQN_WIDTH'] = max(parameters['TX_QUEUE_INDEX_WIDTH'], parameters['RX_QUEUE_INDEX_WIDTH']) + 1
    parameters['EQ_PIPELINE'] = 3
    parameters['TX_QUEUE_PIPELINE'] = 3 + max(parameters['TX_QUEUE_INDEX_WIDTH']-12, 0)
    parameters['RX_QUEUE_PIPELINE'] = 3 + max(parameters['RX_QUEUE_INDEX_WIDTH']-12, 0)
    parameters['CQ_PIPELINE'] = 3 + max(parameters['CQN_WIDTH']-12, 0)

    # TX and RX engine configuration
    parameters['TX_DESC_TABLE_SIZE'] = 1024 #change
    parameters['RX_DESC_TABLE_SIZE'] = 1024 #change
    parameters['RX_INDIR_TBL_ADDR_WIDTH'] = min(parameters['RX_QUEUE_INDEX_WIDTH'], 8)

    # Scheduler configuration
    parameters['TX_SCHEDULER_OP_TABLE_SIZE'] = parameters['TX_DESC_TABLE_SIZE']
    parameters['TX_SCHEDULER_PIPELINE'] = parameters['TX_QUEUE_PIPELINE']
    parameters['TDMA_INDEX_WIDTH'] = 6

    # Interface configuration
    parameters['PTP_TS_ENABLE'] = ptp_ts_enable
    parameters['TX_CPL_ENABLE'] = parameters['PTP_TS_ENABLE']
    parameters['TX_CPL_FIFO_DEPTH'] = 32
    parameters['TX_TAG_WIDTH'] = 16
    parameters['TX_CHECKSUM_ENABLE'] = 1
    parameters['RX_HASH_ENABLE'] = 1
    parameters['RX_CHECKSUM_ENABLE'] = 1
    parameters['LFC_ENABLE'] = 1
    parameters['PFC_ENABLE'] = parameters['LFC_ENABLE']
    parameters['MAC_CTRL_ENABLE'] = 1
    parameters['TX_FIFO_DEPTH'] = 32768
    parameters['RX_FIFO_DEPTH'] = 131072
    parameters['MAX_TX_SIZE'] = 9214
    parameters['MAX_RX_SIZE'] = 9214
    parameters['TX_RAM_SIZE'] = 131072
    parameters['RX_RAM_SIZE'] = 131072

    # RAM configuration
    parameters['DDR_CH'] = 1
    parameters['DDR_ENABLE'] = 0
    parameters['DDR_GROUP_SIZE'] = 1
    parameters['AXI_DDR_DATA_WIDTH'] = 256
    parameters['AXI_DDR_ADDR_WIDTH'] = 32
    parameters['AXI_DDR_ID_WIDTH'] = 8
    parameters['AXI_DDR_MAX_BURST_LEN'] = 256
    parameters['HBM_CH'] = 1
    parameters['HBM_ENABLE'] = 0
    parameters['HBM_GROUP_SIZE'] = parameters['HBM_CH']
    parameters['AXI_HBM_DATA_WIDTH'] = 256
    parameters['AXI_HBM_ADDR_WIDTH'] = 32
    parameters['AXI_HBM_ID_WIDTH'] = 6
    parameters['AXI_HBM_MAX_BURST_LEN'] = 16

    # Application block configuration
    parameters['APP_ID'] = 0x00000000
    parameters['APP_ENABLE'] = 0
    parameters['APP_CTRL_ENABLE'] = 1
    parameters['APP_DMA_ENABLE'] = 1
    parameters['APP_AXIS_DIRECT_ENABLE'] = 1
    parameters['APP_AXIS_SYNC_ENABLE'] = 1
    parameters['APP_AXIS_IF_ENABLE'] = 1
    parameters['APP_STAT_ENABLE'] = 1

    # DMA interface configuration
    parameters['DMA_IMM_ENABLE'] = 0
    parameters['DMA_IMM_WIDTH'] = 32
    parameters['DMA_LEN_WIDTH'] = 16
    parameters['DMA_TAG_WIDTH'] = 16
    parameters['RAM_ADDR_WIDTH'] = (max(parameters['TX_RAM_SIZE'], parameters['RX_RAM_SIZE'])-1).bit_length()
    parameters['RAM_PIPELINE'] = 2

    # PCIe interface configuration
    parameters['AXIS_PCIE_DATA_WIDTH'] = axis_pcie_data_width
    parameters['PF_COUNT'] = 1
    parameters['VF_COUNT'] = 0

    # Interrupt configuration
    parameters['IRQ_INDEX_WIDTH'] = parameters['EQN_WIDTH']

    # AXI lite interface configuration (control)
    parameters['AXIL_CTRL_DATA_WIDTH'] = 32
    parameters['AXIL_CTRL_ADDR_WIDTH'] = 24
    parameters['AXIL_CSR_PASSTHROUGH_ENABLE'] = 0

    # AXI lite interface configuration (application control)
    parameters['AXIL_APP_CTRL_DATA_WIDTH'] = parameters['AXIL_CTRL_DATA_WIDTH']
    parameters['AXIL_APP_CTRL_ADDR_WIDTH'] = 24

    # Ethernet interface configuration
    parameters['AXIS_ETH_DATA_WIDTH'] = axis_eth_data_width
    parameters['AXIS_ETH_SYNC_DATA_WIDTH'] = axis_eth_sync_data_width
    parameters['AXIS_ETH_RX_USE_READY'] = 0
    parameters['AXIS_ETH_TX_PIPELINE'] = 0
    parameters['AXIS_ETH_TX_FIFO_PIPELINE'] = 2
    parameters['AXIS_ETH_TX_TS_PIPELINE'] = 0
    parameters['AXIS_ETH_RX_PIPELINE'] = 0
    parameters['AXIS_ETH_RX_FIFO_PIPELINE'] = 2

    # Statistics counter subsystem
    parameters['STAT_ENABLE'] = 1
    parameters['STAT_DMA_ENABLE'] = 1
    parameters['STAT_PCIE_ENABLE'] = 1
    parameters['STAT_INC_WIDTH'] = 24
    parameters['STAT_ID_WIDTH'] = 12

    extra_env = {f'PARAM_{k}': str(v) for k, v in parameters.items()}

    sim_build = os.path.join(tests_dir, "sim_build",
        request.node.name.replace('[', '-').replace(']', ''))

    cocotb_test.simulator.run(
        python_search=[tests_dir],
        verilog_sources=verilog_sources,
        toplevel=toplevel,
        module=module,
        parameters=parameters,
        sim_build=sim_build,
        extra_env=extra_env,
    )
