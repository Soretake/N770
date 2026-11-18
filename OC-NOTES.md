# SM-N770F (Exynos 9810) Big-Cluster Overclock — Build & Patch Notes

**Target of this build: big (M3 "Mongoose") cluster max = 2314 MHz** (safe first
step). Little cluster (A55, cores 0-3) is **untouched** (stays 1794 MHz).
Benchmark-only overclock: keep the phone actively cooled and on charge, revert
to stock afterwards.

---

## 1. The single value to bump for the next-higher ceiling

Everything is driven by **one** macro:

```
include/linux/n770_oc.h  ->  #define N770_OC_BIG_MAX_KHZ  2314000u
```

Raise it **one real OPP at a time** and re-validate stability each step:

```
2314000 -> 2496000 -> 2652000 -> 2704000
```

Those are the real selectable big-cluster OPPs present in the ECT rate table
(kHz): `1794000 1924000 2002000 2158000 2314000 2496000 2652000 2704000`.
Do **not** pick a value that is not in that list. Voltages are **not** changed —
each OPP uses its stock ECT/ASV voltage (same silicon as Galaxy S9 G960/G965,
which runs this exact cluster to 2704 MHz on these same voltages).

After editing the macro, rebuild (see §4). If you also want the device tree to
match, bump the matching hex values in `exynos9810.dts` (see §3) — but the
kernel-code override alone is what actually lifts the cap on-device.

---

## 2. Why the stock cap is 1794 MHz (root cause)

The ECT/cal-dvfs rate table already exposes OPPs up to 2704 MHz and
`cal_dfs_get_max_freq()` returns the ECT max, so `scaling_available_frequencies`
and `cpuinfo_max_freq` already read 2704000. The **functional** cap of 1794 MHz
is imposed by **three device-tree-driven limiters**, confirmed in source:

| # | Limiter | File | Mechanism |
|---|---------|------|-----------|
| 1 | `policy-max` | `drivers/cpufreq/exynos-acme.c` `set_policy()` | sets initial `policy->max` from DT `policy-max` (0x1b5fd0 = 1794000) |
| 2 | UFC `max-limit` table | `drivers/cpufreq/exynos-ufc.c` `init_ufc_table_dt()` | every big-cluster `cpufreq_max_limit` write is remapped to `limit_freq` = 1794000 → `user_max_qos_req` |
| 3 | hotplug governor | `drivers/soc/samsung/exynos-hotplug_governor.c` | `maxfreq_table[QUAD]`/`[TRIPLE]` = `quad_freq`/`triple_freq` (1794000); applied every policy update via `cpufreq_verify_within_limits()` |

**#3 is the dominant one for benchmarks**: with 3–4 big cores online (any
multi-core load) the hotplug governor re-clamps `policy->max` back to 1794 MHz on
every update — which is exactly why writing `scaling_max_freq` /
`/sys/power/cpufreq_max_limit` / PM-QoS from userspace all snapped back to
1794000. Stock per-core-count caps are: SINGLE=2704, DUAL=2314, TRIPLE=1794,
QUAD=1794 MHz.

Note `exynos-acme.c:init_domain()` only clamps `domain->max_freq` by DT
`max-freq` when `CONFIG_EXYNOS_HOTPLUG_GOVERNOR` is **not** set; it **is** set
here, so `domain->max_freq` = ECT max (2704000) and the OPPs above 1794 are
valid in the freq table — the caps above are the only thing hiding them.

---

## 3. Exactly what was changed

### Kernel code (compiled into `Image` → travels in boot.img)

These lift all three limiters for the big cluster (cal-id `0xb040003`) up to
`N770_OC_BIG_MAX_KHZ`. They work **regardless of which DTB the device loads**
(the Exynos DTB lives in a separate `dtb`/`dtbo` partition, not in boot.img).

- **`include/linux/n770_oc.h`** *(new)* — the ceiling macro + cal-id + docs.
- **`drivers/cpufreq/exynos-acme.c`**
  - `#include <linux/n770_oc.h>`
  - `set_policy()`: for the big cluster, raise `policy-max` up to the ceiling.
- **`drivers/cpufreq/exynos-ufc.c`**
  - `#include <linux/n770_oc.h>`
  - `init_ufc_table_dt()`: for the big cluster + `PM_QOS_MAX_LIMIT` table, set
    each OPP's `limit_freq` to `min(freq, ceiling)` instead of the stock 1794000.
- **`drivers/soc/samsung/exynos-hotplug_governor.c`**
  - `#include <linux/n770_oc.h>`
  - `exynos_hpgov_parse_dt()`: raise `maxfreq_table[DUAL/TRIPLE/QUAD]` to
    `min(ceiling, ECT_max)`.

### Device tree (`arch/arm64/boot/dts/exynos/exynos9810.dts` → `dtb.img`)

Mirrors the code changes so a from-source `dtb.img` is consistent (hex = kHz):

- `cpufreq/domain@1`: `max-freq` and `policy-max` `0x1b5fd0 → 0x234f10`.
- `hotplug_governor`: `triple_freq` and `quad_freq` `0x1b5fd0 → 0x234f10`
  (`dual_freq` was already `0x234f10`).
- `cpufreq-ufc/domain@1/max-limit` table: `limit_freq` column remapped so
  masters ≥ 2314 MHz clamp to `0x234f10` and masters 1924/2002/2158 map to
  themselves.

`0x1b5fd0` = 1794000, `0x234f10` = 2314000, `0x294280` = 2704000 (all kHz).

---

## 4. How to build (reproducible)

Host: Ubuntu 24.04. Toolchains are bundled in-repo
(`toolchain/clang/...clang-r349610-jopp` + `toolchain/gcc-cfp/...-4.9`).

```bash
# one-time host deps
apt-get update && apt-get install -y flex       # bison/bc already present
# a real Python 2 is required for the RKP-CFP (JOPP) vmlinux instrumentation
# (scripts/rkp_cfp/instrument.py is Python 2). Build or provide python2 and put
# a `python` -> python2 shim first on PATH.

export PATH=$PWD/toolchain/gcc-cfp/gcc-cfp-jopp-only/aarch64-linux-android-4.9/bin:$PATH
export PATH=/path/to/python2-shim:$PATH          # `python` must be Python 2.x
export ARCH=arm64 PLATFORM_VERSION=12 ANDROID_MAJOR_VERSION=s
export CONFIG_SECTION_MISMATCH_WARN_ONLY=y

make ARCH=arm64 CROSS_COMPILE=aarch64-linux-android- HOSTCFLAGS=-fcommon exynos9810-r7_defconfig
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-android- HOSTCFLAGS=-fcommon -j"$(nproc)"
# outputs:
#   arch/arm64/boot/Image                       (kernel, raw)
#   arch/arm64/boot/dts/exynos/exynos9810.dtb   (device tree)
```

Host-build gotchas handled above:
- `HOSTCFLAGS=-fcommon` — modern host GCC defaults to `-fno-common`, which breaks
  the in-tree `dtc` build (`multiple definition of yylloc`).
- The Makefile forces `CC = clang` (bundled JOPP clang) with GNU `as`/`ld` via
  `-no-integrated-as`; it finds the assembler through `which $(CROSS_COMPILE)elfedit`,
  so the GCC toolchain **bin dir must be on PATH** and `CROSS_COMPILE` must be the
  **bare** prefix `aarch64-linux-android-` (not an absolute path), or clang
  routes `as` to the host and fails with `unrecognized option '-EL'`.
- `scripts/rkp_cfp/instrument.py` runs via its `#!/usr/bin/env python` shebang,
  so `python` on PATH must be Python 2.

---

## 5. Flashing / delivery (IMPORTANT — read before flashing)

On Exynos 9810 the **device tree is a separate partition** (`dtb`/`dtbo`), **not**
inside boot.img. That is why the overclock is implemented in **kernel code** too:
flashing just the kernel (boot.img) applies the OC via the code override even if
the device keeps its existing DTB.

To build the Odin-flashable `boot.img`/tar you need the **stock/current
boot.img** from the device (to reuse its exact ramdisk + header). Use
`repack_boot.sh` (in this branch) with `magiskboot`:

```bash
./repack_boot.sh stock_boot.img arch/arm64/boot/Image boot.img
tar -H ustar -cf N770-oc-2314.tar boot.img
# flash boot.img (in the tar) as AP in Odin
```

Optional, for the DT changes too: flash a `dtb.img` built from the patched
`exynos9810.dtb` (match the stock `dtb.img` container format first).

**Stock boot image sha256:** _unknown here — fill in from the device's stock
boot.img before flashing so you can always restore it._

---

## 6. Reference artifact sizes / checksums

- Reference prebuilt boot.img (physwizz): **61865984 bytes**.
- This build: `Image` = 30496800 bytes. See `oc-build/*.sha256` for sha256 of the
  OC `Image` / `Image.gz` / `exynos9810.dtb`, and the clean baseline for
  comparison.

---

## 7. 2496 MHz build (step 2)

The 2314 MHz build was **confirmed working on-device** (big cluster reached
2314 MHz under a cooled single-core load; throttles only when uncooled, as
expected). This step raises the ceiling one rung to **2496 MHz** (`0x261600`,
the next real ECT OPP). Nothing else changed — same three limiter patches, same
toolchain/build flow, voltages untouched (stock S9 values).

Edits vs the 2314 build:
- `include/linux/n770_oc.h`: `N770_OC_BIG_MAX_KHZ` `2314000u → 2496000u`.
- `exynos9810.dts` domain@1: `max-freq`/`policy-max` `0x234f10 → 0x261600`.
- `exynos9810.dts` hotplug_governor: `dual_freq`/`triple_freq`/`quad_freq`
  all `→ 0x261600`.
- `exynos9810.dts` UFC `max-limit`: masters ≥ 2496 MHz now clamp to `0x261600`;
  2314/2158/2002/1924 map to themselves.

Artifacts (kept separate from the 2314 set so both can be pulled):
- `oc-build/Image-2496` — raw OC kernel (sha256 in `oc-build/SHA256SUMS-2496`).
- `oc-build/Image.gz-2496`, `oc-build/exynos9810-2496.dtb`.
- `oc-build/N770-OC-2496-AnyKernel3.zip` — flashable zip.

The 2314 artifacts remain at `oc-build/Image`, `oc-build/exynos9810.dtb`,
`oc-build/N770-OC-2314-AnyKernel3.zip` (source state for 2314 is git commit
`3787818c1`). Next rung after validating 2496: `2652000` then `2704000`.

---

## 8. 2652 MHz build (step 3)

Next rung up (owner cooling the SoC to ~33 °C under load, so thermals are a
non-issue). Ceiling → **2652 MHz** (`0x287760`). Same three limiter overrides,
voltages stock.

- `N770_OC_BIG_MAX_KHZ` `2496000u → 2652000u`.
- DT domain@1 `max-freq`/`policy-max` → `0x287760`; hotplug
  `dual`/`triple`/`quad_freq` → `0x287760`; UFC `max-limit` masters ≥ 2652 MHz
  clamp to `0x287760`.
- Artifacts: `oc-build/Image-2652`, `oc-build/Image.gz-2652`,
  `oc-build/exynos9810-2652.dtb`, `oc-build/N770-OC-2652-AnyKernel3.zip`,
  `oc-build/SHA256SUMS-2652`. Next and final rung: `2704000`.
