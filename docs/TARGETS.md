# Targets hi answers to, and the ones it does not

`hi <name>` resolves one name through a ladder - an ssh host first, then four
container backends - and lands you in the same styled session either way. This
file is the reasoning behind that list: what is on it, what was weighed and
left off, and why each answer is settled.

It exists because that reasoning lived nowhere. Every suggestion got
re-litigated from scratch, and nobody outside the repo could tell whether their
runtime had been rejected or simply never considered. The
[compatibility tables](../README.md#compatibility) answer a different pair of
questions - _can hi land a session on that OS_, and _what shell do you end up
in_. This one answers the one that comes first: _can hi reach that thing at
all_.

**Legend:** ✅ shipped, with a suite · 🔷 open · ❌ decided against, not pending.

## Contents

- [What a "yes" costs](#what-a-yes-costs)
- [The five that ship](#the-five-that-ship)
- [Already covered, without a row](#already-covered-without-a-row)
- [Weighed and not shipped](#weighed-and-not-shipped)
- [Open, and the only one](#open-and-the-only-one)
- [What would change an answer](#what-would-change-an-answer)

## What a "yes" costs

A backend is not one function. Adding one touches seven places, and the last
two are the ones that decide most of the verdicts below:

- **a row in `_HI_BACKENDS`** (`hi.sh`) - `<name>|<what a target resolves
  as>|<liveness probe>|<predicate>`. One list, walked by the dispatch and by
  `scripts/doctor.sh`, so a row reaches `hi --doctor` at the same moment it
  reaches `hi`.
- **a predicate**, beside `_hi_is_docker_container`: one `command -v` guard,
  one `[ "$(<query>)" = <literal> ]`, all stderr swallowed.
- **an arm in `_hi_container_cmds`**, filling `probe`/`cp`/`attach` - ask a
  question, stream a file in, hand over a session. Everything past that point
  is backend-agnostic.
- **a lister, a `run_lister` case and the usage line** in `common/targets.sh`,
  written in that file's standalone-POSIX dialect: it is the only file all
  three completions read and the only one fish can run.
- **a fifth copy of the roster in `common/header.sh`**, whose `_hi_probe_launch`
  hardcodes the backends on purpose - `hi.sh` is never sourced in a session,
  and sharing the list would cost the ssh payload bytes for something that
  changes about once a year. `tests/hi/parse_test.sh` greps the two against
  each other so the copy cannot drift.
- **an e2e suite** in `tests/targets/`, registered in `test_runner.sh`'s
  `_HI_TESTS` table. A suite that can only ever skip is worth less than no
  suite.
- **a fixture that can stand the target up**, which for every backend so far
  has meant a container image.

Then the part that is paid by everyone else. `_hi_resolve_backend` runs
**every** predicate, in parallel, on every `hi <target>`; `common/targets.sh`
probes **every** backend on every TAB after `hi ` (GLOSSARY: HI.26). Both costs
land on machines that have none of the runtime in question. The `command -v`
guard inside each predicate short-circuits before the CLI is executed, so the
marginal cost of a row is a fork rather than a daemon round-trip - but it is
still a fork, five times per keystroke instead of four.

That is the test a candidate has to pass: **a row earns a yes by being
something people actually sit in, not by being reachable.**

## The five that ship

| target | what a name resolves as | proven by |
| ------ | ----------------------- | --------- |
| ssh host ✅ | a `Host` entry in `~/.ssh/config`, or any name ssh will take | `tests/targets/ssh_test.sh`, plus `ssh_disconnect_test.sh` (cleanup on an abrupt drop) and `ssh_relay_test.sh` |
| docker ✅ | a running container | `tests/targets/docker_test.sh` - six cases across bash, zsh, fish, dash and busybox `sh` |
| podman ✅ | a running container | `tests/targets/podman_test.sh`, the same six against podman's own image store |
| nomad ✅ | a running allocation, or `alloc/task` | `tests/targets/nomad_test.sh`, against a real `nomad agent -dev` |
| kubernetes ✅ | a running pod, or `pod/container` | `tests/targets/kube_test.sh`, against a real kind cluster |

ssh is checked first and short-circuits the roster entirely, which is why a
name that is both an ssh host and a container name resolves as the ssh host.

## Already covered, without a row

These come up as requests, and all three already work. They need collecting,
not deciding.

| target | why no row is needed |
| ------ | -------------------- |
| **distrobox** and **toolbx** | they _are_ podman (or docker) containers, so the existing rows reach them by name today. The wrinkle worth knowing is not the transport: these share your real `$HOME`, so hi's rc grafts land in the same files your host shells read. That is what GLOSSARY HI.24's tree-exists guard exists for, and [ALTERNATIVES.md](ALTERNATIVES.md#adjacent-tools-and-how-they-compose) has the full account |
| **remote docker contexts** | the docker row shells out to whatever `docker` is on `$PATH`, so `docker context use` and `DOCKER_HOST` are transparent to hi - the daemon being on another machine changes nothing it looks at |
| **AWS SSM `start-session`, `gcloud compute ssh`, `fly ssh console`, Azure Bastion** | anything that terminates in an OpenSSH connection is a `Host` entry away from being an ordinary ssh target, usually a `ProxyCommand` one. The constraint to know is that hi's ssh path multiplexes two calls over a single `ControlMaster` (`_hi_ctl_open`), which is exactly why mosh and Eternal Terminal cannot be ridden - but a `ProxyCommand` is still OpenSSH, so it can |

## Weighed and not shipped

Each of these would need everything in [What a "yes" costs](#what-a-yes-costs),
and each is a "no" for a reason of its own rather than by category.

| target | status | why |
| ------ | ------ | --- |
| `systemd-nspawn` / `machinectl` | ❌ decided against | `machinectl shell` goes through systemd-machined, so it wants root or a polkit prompt on the host - and the people sitting in an nspawn container long enough to want their aliases there are few next to a fifth probe on every TAB for everyone else. The containers themselves would be ideal targets (a full distro, systemd and bash already in them); the audience is what fails the test, not the shape |
| WSL (`wsl -d <distro>`) | ❌ decided against | reachable only from a Windows client, which is already hi's least-proven tier - and a WSL distribution is a machine you can install say-hi _into_ rather than reach for a session at a time: the `.deb` installs into one unchanged, `/etc/profile.d/say-hi.sh` and all. The permanent install is the better answer to the same want |
| `nerdctl` / containerd | ❌ decided against | the CLI is deliberately docker-compatible, which cuts both ways: it means the integration would be trivial, and it means anyone who wants it can have it with `alias docker=nerdctl` before hi ever sees the name. The population with nerdctl and neither docker nor kubectl is not large enough to charge everyone a probe for |
| `crictl` / CRI-O | ❌ decided against | a node-level debugging tool, not a place people sit - it talks to the CRI socket on one node, and the thing you actually want a session in is the pod, which the kubernetes row already resolves. `tests/targets/kube_test.sh` uses `crictl` internally to preload images, which is about the right relationship to it |
| Apptainer / Singularity | ❌ decided against | HPC containers are run-to-completion jobs far more often than long-lived instances, so most of the time there is nothing to exec into. Where there is an instance, the surrounding culture is batch schedulers and `srun`, not an interactive shell you would want styled |
| Proxmox `pct enter` | ❌ decided against | LXC underneath, and only reachable from the PVE node itself as root - so it is the [lxc row](#open-and-the-only-one) with a narrower door. If LXC lands, this is covered by it or it is not worth covering |
| FreeBSD jails (`jexec`), illumos zones (`zlogin`) | ❌ decided against | both are host-local and root-only: you reach the host over ssh first, at which point the jail or zone is a local concern and `hi` is already running there. The transports are also genuinely unlike the container four - no listing that does not need privileges, nothing that answers a liveness probe unprivileged |
| `chroot` | ❌ decided against | no isolation worth the name, no way to enumerate what exists, root-only to enter, and hi's disposable tree lands inside the chroot anyway. There is no question here that a session answers |

Every one of these still works the way it always did, from the other side: ssh
into the host and run `hi` there if say-hi is installed, or accept the host's
own shell. A "no" here is about hi's roster, not about the machine.

## Open, and the only one

| target | status | where it stands |
| ------ | ------ | --------------- |
| `lxc` / `incus` | 🔷 open | the one container runtime with a real audience that hi does not answer to, and the _easiest_ target it could have: an LXC container is normally a full system container running a real distro with systemd and bash in it, so it lands in the top tier of the fallback ladder rather than the aliases-only one |

Two things about it are already settled. **The CLI is the same shape twice
over** - LXD ships `lxc exec <name> -- <cmd>`, Incus (the LinuxContainers fork)
ships `incus exec` with the same arguments - so "which project" is a decision
to make rather than a difficulty, and picking both means two rows everywhere,
not one row with a fallback. Both also answer `info`, which is what the test
harness's `_hi_require_backend` skips on.

**The fixture is the hard part.** Every existing backend suite stands its
target up from a container image; LXD and Incus want a real daemon and a
storage pool on the runner, which is a change to the self-hosted box rather
than a Dockerfile.

[ROADMAP.md](ROADMAP.md#the-session-itself) carries the entry, including the
roster-order checklist of what it would touch.

## What would change an answer

A "no" above is closed, not permanent - but the thing that would reopen one is
specific: **evidence of people sitting in it**, enough to be worth a fork on
every TAB for everyone who has never heard of it. A new exec CLI, a cleaner API
or an easier integration does not move any of these, because none of them are
"no" for being hard.

If you want one reconsidered, the useful shape of the argument is: who is in
these, how often, and what they do today instead.

**Candidates not yet ruled on** — anything that is neither on a table above nor
the open row — are collected in
[ROADMAP.md](ROADMAP.md#in-repo-code-work)'s _second wave of target candidates_
entry, each with a first read and no verdict. They land here as rows, one way
or the other, as they are decided.
