# Running on 1 GB RAM

The Taishan Pi is available with 1 GB of LPDDR4. That is the tightest
configuration Home Assistant OS runs on, and it needs some attention. This
page describes what the system actually does with 1 GB, and what to change.

---

## Where the memory goes

Home Assistant OS itself is lean — the root filesystem is read-only EROFS and
the only writable parts are the overlay and the data partition. The memory
cost comes from the Docker containers that Supervisor runs.

| Consumer | Typical usage | Notes |
|:-|:-|:-|
| Kernel + systemd + base services | ~150 MB | Includes NetworkManager, systemd, the journal |
| Supervisor | ~120 MB | The largest single user-space process |
| Home Assistant Core | ~350–500 MB | Grows with the number of integrations and entities |
| Add-ons | varies | The Database and SSH add-ons are cheap; heavy add-ons are not |
| zram swap (compressed) | up to 25 % of RAM | See below |
| swapfile | 1 GiB minimum | On disk in `hassos-data`, but it consumes page cache |
| Docker overhead | ~50 MB | containerd, shim processes |

**Rule of thumb:** Core plus Supervisor need roughly 500–650 MB before
add-ons. On 1 GB that leaves very little headroom, and the memory pressure
will show up as sluggish dashboards and slow automation runs rather than as
a crash.

---

## What the OS does automatically

The following is upstream behaviour — it is already tuned for small systems
and you do not need to change it.

### zram

`/usr/libexec/haos-zram` sets up three zram devices:

| Device | Size | Purpose |
|:-|:-|:-|
| `zram0` | 25 % of `MemTotal` | Swap — 256 MB on a 1 GB board |
| `zram1` | 32 MB | `/var` |
| `zram2` | 32 MB | `/tmp` |

The kernel config has `CONFIG_ZRAM=y`, `CONFIG_ZRAM_BACKEND_LZ4=y`,
`CONFIG_ZSWAP=y` and `CONFIG_ZSWAP_DEFAULT_ON=y`. zram is compressed in
RAM, so 256 MB of zram swap costs far less than 256 MB of real memory.

### swapfile

`/usr/libexec/haos-swapfile` creates `/mnt/data/swapfile`. The size defaults
to 33 % of RAM, **clamped to a minimum of 1 GiB and a maximum of 4 GiB**.

On a 1 GB board that means a 1 GiB swapfile — larger than the physical RAM.
That is intentional: it gives the kernel somewhere to page out to when RAM
is exhausted, at the cost of eMMC space and I/O. On a 16 GB eMMC there is
plenty of room.

### CPU governor

The board kernel config sets
`CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE=y`, so the CPU runs at full clock.
The `ondemand` governor would save a little power but makes Home Assistant
responses noticeably slower.

---

## Recommended tuning for 1 GB

### 1. Limit the Docker log size

Docker's default JSON log driver keeps unbounded logs. On a small eMMC that
is a slow disk leak.

Create `/etc/docker/daemon.json` override through the Supervisor API or by
editing the overlay:

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

The upstream overlay already ships
`buildroot-external/rootfs-overlay/etc/docker/daemon.json`; extend it
rather than replacing it, and keep the existing settings.

### 2. Reduce the number of add-ons

The Home Assistant Core container is the largest consumer. Trim integrations
you do not use — every integration adds a fixed overhead plus its entity
count.

### 3. Reduce the recorder database

The default recorder keeps 10 days of state. On a 1 GB board:

```yaml
# configuration.yaml
recorder:
  purge_keep_days: 2
  db_url: sqlite:////data/home-assistant_v2.db
```

### 4. Keep the data partition healthy

```bash
ha core info          # current state
ha resolution info    # supervisor and plugin versions
```

### 5. Watch the memory trend

```bash
# On the device, over SSH
free -h
cat /proc/meminfo | grep -E "MemAvailable|Zswap|Zram"
```

`MemAvailable` is the number that matters. Below ~150 MB, Home Assistant
will start feeling sluggish.

---

## Verifying the memory configuration

On a booted device:

```bash
# zram devices
zramctl

# The swapfile
swapon --show
ls -lh /mnt/data/swapfile

# Memory summary
free -h

# Container memory usage
ha supervisor info
docker stats --no-stream
```

Expected on a 1 GB board:

| Item | Expected |
|:-|:-|
| `MemTotal` | ~975 MB (the kernel reserves some) |
| zram0 size | ~244 MB |
| swapfile | 1.0 GiB |
| `MemAvailable` at idle | 300–500 MB, after Core has been running a while |

---

## Upgrading to 8 GB later

The image is identical across RAM sizes. The DDR training blob
(`rk3566_ddr_1056MHz_v1.18.bin`) covers the 1/2/4/8 GB LPDDR4 variants.

The only thing to change is the swapfile sizing, if you want it to follow
the new RAM size. It is computed automatically from `MemTotal` at boot, so
nothing needs to change — but if you pinned it, remove the override:

```bash
# If /etc/default/haos-swapfile exists, delete it to restore the default
rm -f /etc/default/haos-swapfile
```

---

## Constraints to keep in mind when adding features

* The 1 GB board has **no headroom for a desktop, a browser or a compiler**.
  This image ships none of those, and that is deliberate.
* Add-on images are the usual memory surprise. Check an add-on's documented
  memory use before installing it.
* `systemd-journald` is configured for a bounded journal (`journald.conf` in
  the upstream overlay). Keep it that way; an unbounded journal on a 16 GB
  eMMC can grow to gigabytes.
* The EROFS root filesystem means there is no package manager and no way to
  `apt install` your way out of a missing feature. Anything extra belongs in
  an add-on.
