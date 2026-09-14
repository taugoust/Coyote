/* Device-free execution of the production ioctl against RTL discovery values. */
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#define __iomem
#define __user
#define CAP_SYS_ADMIN 1
#define READ_ONCE(x) (x)
#define IS_ERR(x) (!(x))
#define PTR_ERR(x) (-ENOMEM)
#define __packed __attribute__((packed))
#include "ioctl_abi.h"
#define FPGA_SHELL_CNFG_SIZE (32UL * 1024UL)
struct shell_config { uint64_t reserved[11], service_ctrl_cnfg, service_ctrl_base; };
struct bus_driver_data { struct shell_config *shell_cnfg; };
struct reconfig_dev { int rcnfg_lock; };
static int privileged = 1, touches;
static int capable(int cap) { (void)cap; return privileged; }
static void *memdup_user(void *p, size_t n) { void *q=malloc(n); if(q) memcpy(q,p,n); return q; }
static int copy_to_user(void *d, const void *s, size_t n) { memcpy(d,s,n); return 0; }
static void mutex_lock(int *p) { (void)p; }
static void mutex_unlock(int *p) { (void)p; }
static void writeq(uint64_t v, void *p) { touches++; memcpy(p,&v,8); }
static uint64_t readq(void *p) { uint64_t v; touches++; memcpy(&v,p,8); return v; }
#define wmb() ((void)0)
#define kfree free
#include "ioctl_under_test.c"
int main(int argc, char **argv) {
    assert(argc == 4);
    uint64_t memory[FPGA_SHELL_CNFG_SIZE / 8] = {0};
    struct bus_driver_data bus = {(struct shell_config *)memory};
    struct reconfig_dev dev = {0};
    struct cyt_service_ctrl_batch batch = {.interface_version=1, .count=1};
    bus.shell_cnfg->service_ctrl_cnfg = strtoull(argv[1],0,16);
    bus.shell_cnfg->service_ctrl_base = strtoull(argv[2],0,16);
    unsigned relative = strtoul(argv[3],0,16);
    unsigned bytes = bus.shell_cnfg->service_ctrl_cnfg >> 32;
    privileged=0;
    assert(service_ctrl_batch_ioctl(&dev,&bus,(unsigned long)&batch)==-EPERM);
    assert(touches==0);
    privileged=1;
    if (!(bus.shell_cnfg->service_ctrl_cnfg & 1)) {
        assert(service_ctrl_batch_ioctl(&dev,&bus,(unsigned long)&batch)==-ENODEV);
        assert(touches==0); return 0;
    }
    batch.ops[0].offset=relative;
    memory[(bus.shell_cnfg->service_ctrl_base + relative)/8]=0x123456789abcdef0ULL;
    assert(service_ctrl_batch_ioctl(&dev,&bus,(unsigned long)&batch)==0);
    assert(batch.ops[0].value==0x123456789abcdef0ULL);
    batch.ops[0].offset=bytes-8; batch.ops[0].flags=1; batch.ops[0].value=42;
    assert(service_ctrl_batch_ioctl(&dev,&bus,(unsigned long)&batch)==0);
    assert(memory[(bus.shell_cnfg->service_ctrl_base+bytes-8)/8]==42);
    touches=0;
    batch.ops[0].offset=bytes;
    assert(service_ctrl_batch_ioctl(&dev,&bus,(unsigned long)&batch)==-EINVAL);
    batch.ops[0].offset=1;
    assert(service_ctrl_batch_ioctl(&dev,&bus,(unsigned long)&batch)==-EINVAL);
    assert(touches==0);
    return 0;
}
