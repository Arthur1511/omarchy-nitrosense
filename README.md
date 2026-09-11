# NitroSense

Live temperatures, fan speed and fan-mode control for **Acer Nitro** laptops,
as an Omarchy bar widget (Quattro).

Click the bar pill to open the details popup:

- **Температура** — CPU, GPU and system (mainboard) temperatures
- **Вентиляторы** — live CPU/GPU fan speed in RPM
- **Режим вентилятора** — the four Acer fan modes: Авто (Auto) · Тихий (Quiet) · Баланс (Balance) · Игра (Game)

The bar pill shows `CPU temp · CPU fan RPM`. All data is read straight from
the embedded controller (EC) — no daemon, no polling service, no network.

## Hardware support

Tested on an **Acer Nitro AN515-55** (ECS AN515-46-class EC firmware).

The register map mirrors [Linux-NitroSense](https://github.com/LinuxNitro/Linux-NitroSense):

| metric | EC register(s) |
|---|---|
| CPU temp | `0xB0` |
| System temp | `0xB3` |
| GPU temp | `0xB6` |
| CPU fan RPM | `0x13` (hi), `0x14` (lo) |
| GPU fan RPM | `0x15` (hi), `0x16` (lo) |
| CPU fan mode | `0x22` (auto `0x04` / turbo `0x08`) |
| GPU fan mode | `0x21` (auto `0x10` / turbo `0x20`) |
| Nitro mode | `0x2C` (quiet `0x00` / balance `0x01` / extreme `0x04`) |

Other Acer Nitro models are **strictly read-only**: `nitro-ec` verifies the
DMI identity (vendor + product name) against a reviewed allowlist before every
EC write and refuses otherwise (fail closed). Only firmware families
register-mapped and verified on real hardware may be added to the allowlist.

If the EC is unreachable the widget degrades gracefully and shows a readable
error instead of crashing the bar.

## Install

```sh
omarchy plugin add https://github.com/bobster05/omarchy-nitrosense.git --enable
cd ~/.config/omarchy/plugins/io.github.bobster05.nitrosense
sudo ./setup.sh
sudo usermod -aG nitro "$USER"
```

Then **log out and back in** so the `nitro` group membership takes effect.

### What `setup.sh` does (privileges)

The EC is reached through `/dev/ec`, provided by the `acpi_ec` kernel module
(AUR for Arch/Manjaro: `acpi_ec-dkms-git`). These devices are root-only by
default. Instead of running the widget as root, `setup.sh`:

1. creates the `nitro` group,
2. loads `acpi_ec` now and on every boot (`/etc/modules-load.d/nitro-ec.conf`),
3. installs udev rules giving members of `nitro` group RW access to
   `/dev/ec` and the debugfs EC interface (`/etc/udev/rules.d/99-nitro-ec.rules`,
   `99-nitro-dmi.rules`),
4. applies the rules immediately.

The widget itself runs **unprivileged**, as your normal user — the only thing
the user gains is EC access via group `nitro`.

## Usage

- **Left click** the pill toggles the details popup; **Escape** closes it.
- The four buttons write the selected mode to the EC immediately
  (Auto and Quiet also reset the fans to automatic control).
- The mode line at the top shows the *stored* Nitro mode and fan state, so it
  reflects changes made outside the widget too (keyboard shortcut, Windows,
  `nitro-ec set`).

`nitro-ec` is a stateless CLI that does the same job without the UI:

```sh
./nitro-ec status          # JSON: temps, fan RPM, modes, hwSupported, writesAllowed
./nitro-ec set quiet       # quiet | balance | game | auto

`set` is refused on hardware not in the reviewed DMI allowlist (exit code 1,
no write). To force a write on unsupported hardware, on your own risk:

```sh
./nitro-ec set quiet --force   # prints a warning; may damage the EC
```
```

## Configure

Move the widget between bar sections:

```sh
omarchy bar move io.github.bobster05.nitrosense --section right
```

## Uninstall

```sh
# optional: revoke EC access first (from the plugin folder)
sudo ./setup.sh --uninstall

omarchy plugin remove io.github.bobster05.nitrosense
```

`setup.sh --uninstall` removes the udev rules, the module autoload config and
unloads `acpi_ec`. Group membership can be cleaned up with
`sudo gpasswd -d "$USER" nitro` (+ `sudo groupdel nitro` if empty).

## Security notes

- The plugin is a normal Omarchy bar widget; it runs inside the long-lived
  `omarchy-shell` process with your user permissions.
- The sole extra privilege is **group-level RW access to the EC device**
  via the `nitro` group — a design choice to avoid running anything as root
  at runtime. Only members of `nitro` can touch fan/temp registers.
- Setup must run once with `sudo`; it only creates a group, a module autoload
  config and two udev rules — it does not run any daemon.
- EC writes are **fail-closed**: `nitro-ec` verifies the DMI identity against
  a reviewed allowlist before every write and refuses otherwise (`--force`
  opts in with a warning).
- Hard limits on helper execution: `nitro-ec` carries the fixed shebang
  `#!/usr/bin/python3` — the kernel execs that absolute interpreter directly,
  so `/usr/bin/env` and ambient `PATH` are never consulted. On Arch the target
  is the system-managed `/usr/bin/python3` (root-owned, distro-updated).
  The helper never spawns a shell or an external binary (the CPU-temp
  fallback reads `/sys/class/hwmon` directly); the widget bounds the helper's
  output (64 KB) and SIGKILLs the helper if it exceeds a 3 s deadline.

## License

MIT — see [LICENSE](LICENSE). Register map and EC access methodology inspired
by the open source [Linux-NitroSense](https://github.com/LinuxNitro/Linux-NitroSense) project.