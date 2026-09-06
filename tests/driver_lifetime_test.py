#!/usr/bin/env python3
"""Device-free fault injection into production pin/worker/context code.

Kernel primitives are mocked, not the lifecycle decisions. This does not model
DMA hardware, kernel scheduling or replace lockdep/KASAN runtime qualification.
Run with Python and a C compiler supplied by the consuming Nix environment.
"""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]

def function(path, signature):
    text = (root / path).read_text()
    start = text.index(signature)
    end = text.index('{', start)
    depth = 1
    end += 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]

shim = r'''
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#define KERNEL_VERSION(a,b,c) (((a)<<16)|((b)<<8)|(c))
#define LINUX_VERSION_CODE KERNEL_VERSION(7,1,9)
#define PAGE_SIZE 4096UL
#define FOLL_WRITE 1
#define FOLL_LONGTERM 2
struct mm_struct { int refs; };
struct task_struct { int refs; struct mm_struct *mm; };
struct page { int refs; };
struct vm_area_struct { unsigned long vm_start, vm_end; bool huge; };
static struct vm_area_struct area = {4096, 4096*9, false};
static struct page backing[8];
static long injected;
static int mmap_locked, unpinned, pin_calls;
static bool missing_vma;
static void mmap_read_lock(struct mm_struct *mm) { assert(!mmap_locked); mmap_locked=1; }
static void mmap_read_unlock(struct mm_struct *mm) { assert(mmap_locked); mmap_locked=0; }
static struct vm_area_struct *find_vma(struct mm_struct *mm, unsigned long start) {
    assert(mmap_locked); return missing_vma ? NULL : &area;
}
static bool is_vm_hugetlb_page(struct vm_area_struct *vma) { assert(vma); return vma->huge; }
static long pin_user_pages_remote(struct mm_struct *mm, unsigned long start,
 unsigned int count, int flags, struct page **pages, void *locked) {
    assert(mmap_locked && !locked); pin_calls++;
    for (long i=0; i<injected; i++) { backing[i].refs++; pages[i]=&backing[i]; }
    return injected;
}
static void unpin_user_pages(struct page **pages, unsigned long count) {
    assert(count<=8);
    for (unsigned long i=0; i<count; i++) { assert(pages[i] && pages[i]->refs==1); pages[i]->refs--; unpinned++; }
}
#include "vfpga_pin.h"
#define N_CTID_MAX 4
#define BUFF_NEEDS_EXP_SYNC_RET_CODE 1
#define BUG_ON(x) assert(!(x))
#define dbg_info(...) ((void)0)
#define pr_err(...) ((void)0)
#define READ_ONCE(x) (x)
#define container_of(p,t,m) ((t *)((char *)(p)-offsetof(t,m)))
#define spin_lock_irqsave(p,f) ((f)=0)
#define spin_unlock_irqrestore(p,f) ((void)0)
struct pid { int refs; struct task_struct *task; };
#define PIDTYPE_PID 0
static struct task_struct *get_pid_task(struct pid *p, int type) {
 if(!p || !p->task) return NULL;
 p->task->refs++;
 return p->task;
}
static struct mm_struct *get_task_mm(struct task_struct *t) {
 if(!t->mm) return NULL;
 t->mm->refs++;
 return t->mm;
}
static void mmput(struct mm_struct *mm) { assert(mm->refs>0); mm->refs--; }
static void put_task_struct(struct task_struct *t) { assert(t->refs>0); t->refs--; }
struct tlb_metadata { uint64_t page_mask; int page_shift; };
struct bus_driver_data { struct tlb_metadata *ltlb_meta, *stlb_meta; int n_pages_in_huge, dif_order_page_shift; };
struct work_struct { int unused; };
struct mutex { int held; };
struct vfpga_dev {
 int id, irq_lock, num_free_ctid_chunks;
 struct bus_driver_data *bd_data;
 bool stopping;
 struct mutex pid_lock, mmu_lock;
 uint64_t context_generation[N_CTID_MAX];
 int pid_array[N_CTID_MAX];
 struct pid *context_pid[N_CTID_MAX];
};
struct vfpga_irq_pfault {
 struct vfpga_dev *device;
 uint64_t generation, vaddr;
 int len, ctid, stream;
 bool wr;
 struct work_struct work_pfault;
};
static int mapped, restarted, dropped, freed;
static void put_pid(struct pid *p) { if(p) { assert(p->refs==1); p->refs--; } }
static void mutex_lock(struct mutex *m) { assert(!m->held); m->held=1; }
static void mutex_unlock(struct mutex *m) { assert(m->held); m->held=0; }
static void kfree(void *p) { freed++; free(p); }
static int mmu_handler_gup(struct vfpga_dev *d, uint64_t a, int l, int c, int s, int p, int b) {
 assert(d->pid_lock.held && d->mmu_lock.held); mapped++; return 0;
}
static void drop_irq_pfault(struct vfpga_dev *d, bool w, int c) { dropped++; }
static void restart_mmu(struct vfpga_dev *d, bool w, int c) { restarted++; }
'''
code = shim + '\n' + function('driver/src/vfpga/vfpga_ops.c', 'static void retire_context(')
code += '\n' + function('driver/src/vfpga/vfpga_isr.c', 'void vfpga_pfault_handler(')
code += r'''
struct hlist_node { struct hlist_node *next, **pprev; };
struct user_pages { struct hlist_node entry; int releases, host; bool needs_explicit_sync; };
static struct hlist_node *user_buff_map[1][N_CTID_MAX][2];
#define hash_for_each_safe(table,bkt,tmp,obj,member) \
 for((bkt)=0;(bkt)<2;(bkt)++) \
 for(struct hlist_node *n=(table)[bkt]; \
 n && ((tmp)=n->next, (obj)=container_of(n,struct user_pages,member),1); n=(tmp))
static void hash_del(struct hlist_node *node) {
 assert(node->pprev); *node->pprev=node->next;
 if(node->next) node->next->pprev=node->pprev;
 node->pprev=NULL;
}
static int release_user_pages_entry(struct vfpga_dev *d, struct user_pages *p, int pid, int dirty) {
 assert(!p->entry.pprev); assert(!p->releases); p->releases++;
 return 0;
}
'''
code += function('driver/src/vfpga/vfpga_gup.c', 'int tlb_put_user_pages_ctid(')
code += r'''
#define HOST_ACCESS 1
#define CARD_ACCESS 0
struct pf_aligned_desc { uint64_t vaddr; unsigned int n_pages; int ctid; bool hugepages; };
static struct user_pages *map_present(struct vfpga_dev *d, struct pf_aligned_desc *p) { return NULL; }
static struct user_pages *tlb_get_user_pages(struct vfpga_dev *d, struct pf_aligned_desc *p, int pid, struct task_struct *t, struct mm_struct *mm, int block) { return NULL; }
static void tlb_map_gup(struct vfpga_dev *d, struct pf_aligned_desc *p, struct user_pages *u, int pid) {}
static void tlb_unmap_gup(struct vfpga_dev *d, struct user_pages *u, int pid) {}
static void migrate_to_host(struct vfpga_dev *d, struct user_pages *u) {}
static void migrate_to_card(struct vfpga_dev *d, struct user_pages *u) {}
'''
code += function('driver/src/vfpga/vfpga_gup.c', 'int mmu_handler_gup(').replace('int mmu_handler_gup(', 'int tested_mmu_handler_gup(', 1)
code += r'''
static void fault(struct vfpga_dev *d, int ctid, uint64_t generation) {
 struct vfpga_irq_pfault *f=calloc(1,sizeof(*f));
 f->device=d; f->ctid=ctid; f->generation=generation;
 vfpga_pfault_handler(&f->work_pfault);
 assert(!d->pid_lock.held && !d->mmu_lock.held);
}
int main(void) {
 struct mm_struct mm={0}; struct task_struct task={0};
 long results[]={-ENOMEM,-EFAULT,0,1,2,3,4};
 for(unsigned int i=0;i<sizeof(results)/sizeof(*results);i++) {
   struct page *pages[4]={0}; injected=results[i]; unpinned=0;
   int result=coyote_pin_pages(&task,&mm,4096,4,false,pages);
   assert(!mmap_locked);
   assert((result==0)==(injected==4));
   assert(unpinned==(injected>0 && injected<4 ? injected : 0));
   if(!result) unpin_user_pages(pages,4);
   for(int j=0;j<4;j++) assert(backing[j].refs==0);
 }
 struct page *pages[4]={0}; injected=4;
 int before=pin_calls;
 missing_vma=true; assert(coyote_pin_pages(&task,&mm,4096,4,false,pages)==-EFAULT);
 missing_vma=false;
 assert(coyote_pin_pages(&task,&mm,0,4,false,pages)==-EFAULT);
 area.huge=true; assert(coyote_pin_pages(&task,&mm,4096,4,false,pages)==-EFAULT);
 area.huge=false;
 assert(coyote_pin_pages(&task,&mm,4096,9,false,pages)==-EFAULT);
 assert(coyote_pin_pages(&task,&mm,4096,0,false,pages)==-EINVAL);
 assert(pin_calls==before && !mmap_locked);
 struct pid old={.refs=1}, replacement={.refs=1};
 struct vfpga_dev d={0}; d.context_pid[0]=&old; d.pid_array[0]=123; d.context_generation[0]=1;
 fault(&d,0,1); assert(mapped==1 && restarted==1);
 mutex_lock(&d.pid_lock); mutex_lock(&d.mmu_lock);
 retire_context(&d,0);
 mutex_unlock(&d.mmu_lock); mutex_unlock(&d.pid_lock);
 assert(!old.refs && !d.context_pid[0] && !d.pid_array[0]);
 fault(&d,0,1); assert(mapped==1);
 // Reuse both numeric CTID and PID: queued old incarnation must still reject.
 d.context_pid[0]=&replacement; d.pid_array[0]=123; d.context_generation[0]++;
 fault(&d,0,1); assert(mapped==1);
 fault(&d,0,d.context_generation[0]); assert(mapped==2);
 d.stopping=true; fault(&d,0,d.context_generation[0]); assert(mapped==2);
 fault(&d,-1,0); fault(&d,N_CTID_MAX,0); assert(mapped==2 && freed==7);
 // Colliding hash entries and repeated cleanup release each entry once.
 struct bus_driver_data bus={0};
 struct user_pages a={0}, b={0}, c={0}; d.bd_data=&bus;
 user_buff_map[0][0][0]=&a.entry; a.entry.pprev=&user_buff_map[0][0][0];
 a.entry.next=&b.entry; b.entry.pprev=&a.entry.next;
 user_buff_map[0][0][1]=&c.entry; c.entry.pprev=&user_buff_map[0][0][1];
 assert(!tlb_put_user_pages_ctid(&d,0,123,1));
 assert(a.releases==1 && b.releases==1 && c.releases==1);
 assert(!tlb_put_user_pages_ctid(&d,0,123,1));
 assert(a.releases==1 && b.releases==1 && c.releases==1);
 // Execute production mmu_handler's missing-task/mm branches and ref unwind.
 d.context_pid[0]=NULL;
 assert(tested_mmu_handler_gup(&d,4096,64,0,1,123,-1)==-ESRCH);
 struct task_struct exiting={0}; struct pid owner={1,&exiting};
 d.context_pid[0]=&owner;
 assert(tested_mmu_handler_gup(&d,4096,64,0,1,123,-1)==-ESRCH);
 assert(!exiting.refs);
 exiting.mm=&mm; missing_vma=true;
 assert(tested_mmu_handler_gup(&d,4096,64,0,1,123,-1)==-EFAULT);
 assert(!exiting.refs && !mm.refs && !mmap_locked); missing_vma=false;
 puts("PASS: negative/partial/full pins, exact unwind, VMA change, retired/reused/stopping fault work, repeated colliding-map cleanup, exited task/mm refs");
}
'''
with tempfile.TemporaryDirectory() as tmp:
    source = Path(tmp) / 'test.c'
    binary = Path(tmp) / 'test'
    source.write_text(code)
    subprocess.run([os.environ.get('CC', 'cc'), '-std=gnu11', '-Wall', '-Wextra',
                    '-Wno-unused-parameter', '-Wno-unused-but-set-variable',
                    '-fsanitize=address,undefined', '-I'+str(root/'driver/include/vfpga'),
                    str(source), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
