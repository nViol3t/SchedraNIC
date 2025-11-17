# SPDX-License-Identifier: BSD-2-Clause-Views
# Copyright (c) 2019-2023 The Regents of the University of California

# 用户 make 只是入口，负责把编译请求转交给内核
# 真正的编译必须由内核构建系统来做，确保内核模块与内核本身一致
# 模块源码放在任何地方都能编译、不用把模块源码放进内核源码树、生成的.ko 文件一定能匹配当前内核
ifneq ($(KERNELRELEASE),)

# object files to build
# xxx-y：始终编译进 xxx.o（静态包含）
# xxx-$(CONFIG_FOO)：根据 Kconfig 配置条件，决定是否把某个文件编进来
# obj-m 表示目标文件要编译成可加载的内核模块文件，即.ko文件
obj-m += mqnic.o
mqnic-y += mqnic_main.o
mqnic-y += mqnic_devlink.o
mqnic-y += mqnic_res.o
mqnic-y += mqnic_reg_block.o
mqnic-y += mqnic_irq.o
mqnic-y += mqnic_dev.o
mqnic-y += mqnic_if.o
mqnic-y += mqnic_port.o
mqnic-y += mqnic_netdev.o
mqnic-y += mqnic_sched_block.o
mqnic-y += mqnic_scheduler.o
mqnic-y += mqnic_ptp.o
mqnic-y += mqnic_i2c.o
mqnic-y += mqnic_board.o
mqnic-y += mqnic_clk_info.o
mqnic-y += mqnic_stats.o
mqnic-y += mqnic_tx.o
mqnic-y += mqnic_rx.o
mqnic-y += mqnic_cq.o
mqnic-y += mqnic_eq.o
mqnic-y += mqnic_ethtool.o

ifneq ($(DEBUG),)
ccflags-y += -DDEBUG
endif

else

ifneq ($(KERNEL_SRC),)
# alternatively to variable KDIR accept variable KERNEL_SRC as used in
# PetaLinux/Yocto for example
KDIR ?= $(KERNEL_SRC)
endif

KDIR ?= /lib/modules/$(shell uname -r)/build

all: modules

help modules modules_install clean:
	$(MAKE) -C $(KDIR) M=$(shell pwd) $@

install: modules_install

endif
