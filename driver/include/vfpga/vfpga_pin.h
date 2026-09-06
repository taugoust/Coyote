/* SPDX-License-Identifier: GPL-2.0-only */
#ifndef COYOTE_VFPGA_PIN_H
#define COYOTE_VFPGA_PIN_H

/* Return only a complete owned set of pins. On every error the caller owns
 * zero pins, including a positive short GUP result. mmap_lock protects both
 * the VMA classification and the remote pin operation (locked=NULL). */
static inline int coyote_pin_pages(struct task_struct *task, struct mm_struct *mm,
                                  unsigned long start, unsigned int count,
                                  bool huge, struct page **pages)
{
    long pinned;
    struct vm_area_struct *vma;

    if (!count || count > INT_MAX)
        return -EINVAL;
    mmap_read_lock(mm);
    vma = find_vma(mm, start);
    if (!vma || start < vma->vm_start ||
        (vma->vm_end - start) / PAGE_SIZE < count ||
        !!is_vm_hugetlb_page(vma) != huge) {
        mmap_read_unlock(mm);
        return -EFAULT;
    }
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 5, 0)
    pinned = pin_user_pages_remote(mm, start, count, FOLL_WRITE | FOLL_LONGTERM, pages, NULL);
#elif LINUX_VERSION_CODE >= KERNEL_VERSION(5, 9, 0)
    pinned = pin_user_pages_remote(mm, start, count, FOLL_WRITE | FOLL_LONGTERM, pages, NULL, NULL);
#elif LINUX_VERSION_CODE >= KERNEL_VERSION(5, 4, 0)
    pinned = pin_user_pages_remote(task, mm, start, count, FOLL_WRITE | FOLL_LONGTERM, pages, NULL, NULL);
#else
    pinned = get_user_pages_remote(task, mm, start, count, 1, pages, NULL, NULL);
#endif
    mmap_read_unlock(mm);
    if (pinned == count)
        return 0;
    if (pinned > 0) {
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 4, 0)
        unpin_user_pages(pages, pinned);
#else
        for (long i = 0; i < pinned; i++)
            put_page(pages[i]);
#endif
    }
    return pinned < 0 ? (int)pinned : -EFAULT;
}
#endif
