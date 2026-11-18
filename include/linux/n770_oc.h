/* SPDX-License-Identifier: GPL-2.0 */
/*
 * n770_oc.h - SM-N770F (Exynos 9810) big-cluster CPU overclock control
 *
 * Big cluster  = Exynos-M3 "Mongoose" cores 4-7, cpufreq cal-id 0xb040003.
 * Little cluster (A55, cores 0-3, cal-id 0xb040002) is NOT touched.
 *
 * Stock behaviour: the M3 cluster is functionally capped at 1794 MHz even
 * though the ECT/cal-dvfs rate table already exposes OPPs up to 2704 MHz
 * (with Samsung's own S9-equivalent voltages, same silicon). The cap is
 * imposed by three *device-tree driven* limiters, all re-applied here in
 * kernel code so the overclock travels with the boot.img kernel regardless
 * of which DTB the device loads from its separate dtb partition:
 *
 *   1. exynos-acme.c       set_policy()        -> policy->max   (DT policy-max)
 *   2. exynos-ufc.c        init_ufc_table_dt() -> limit_freq    (DT max-limit)
 *   3. exynos-hotplug_governor.c maxfreq_table -> QUAD/TRIPLE   (DT quad/triple_freq)
 *
 * Real selectable big-cluster OPPs present in the ECT table (kHz):
 *   1794000 1924000 2002000 2158000 2314000 2496000 2652000 2704000
 *
 * =====================================================================
 *  >>> THE SINGLE VALUE TO BUMP to raise the overclock ceiling <<<
 *  Must be one of the OPP values above. Raise ONE step at a time and
 *  re-validate stability (stress + benchmark, actively cooled, on charge):
 *     2314000 -> 2496000 -> 2652000 -> 2704000
 *  Voltages are NOT changed; each OPP uses its stock ECT/ASV voltage.
 * =====================================================================
 */
#ifndef _LINUX_N770_OC_H
#define _LINUX_N770_OC_H

/* Big-cluster overclock ceiling, in kHz. Ladder: 2314/2496 validated; now 2652000. */
#define N770_OC_BIG_MAX_KHZ	2652000u

/* cpufreq cal-id of the big (M3) cluster - used to gate the override. */
#define N770_OC_BIG_CAL_ID	0x0b040003u

#endif /* _LINUX_N770_OC_H */
