# tsis1Linux infrastructure scripts

Scripts that set up users, permissions, SSH and the systemd service for the
tsis1Linux todo API on two Ubuntu 24.04 machines (OCI, ARM64):

- **mainapp**: public. nginx and the Go API.
- **main-db**: private, no public IP. PostgreSQL 16 and nightly backups.

Every script is idempotent: running it twice changes nothing the second time.
All scripts must run as root (`sudo bash <script>`), take the machine role as an
argument (`app` or `db`) where it matters, and print what they did.

## Role table

| Role | Account / group | Machine | Permissions | Superuser permissions |
|---|---|---|---|---|
| Administrator | `admins` group, personal user | both | Full shell access; manages configs, packages and users | Full sudo, no password (SSH key is the authentication) |
| Automation bot | `deploy` user, `deployers` group | mainapp | Owns `/opt/tsis1linux`; uploads releases and moves the `current` symlink over SSH (key only, `restrict,pty`) | `systemctl restart tsis1linux.service` only |
| Auditor | `auditor` user, `auditors` group | both | Read-only: logs (`adm`, `systemd-journal`), sudo rules and `pg_hba.conf` (ACL). No access to secrets or backups | None |
| API service account | `tsis1linux` | mainapp | Runs the API; no login shell, no home; cannot write its own binaries or read the secrets file | None |
| Database service account | `postgres` | main-db | Owns the data directory and `/var/backups/tsis1linux`; runs the backup job | None |
| Web server account | `www-data` | mainapp | nginx worker processes | None |

## Scripts

| Script | Runs on | What it does |
|---|---|---|
| `setup-users.sh app\|db` | both | Creates groups, users and group memberships; checks service accounts |
| `setup-fs.sh app\|db` | both | Directory layout, secrets file, systemd unit, nginx site, backup job |
| `setup-sudoers.sh app\|db` | both | One validated file per role in `/etc/sudoers.d/` |
| `setup-perms.sh app\|db` | both | ACLs that give the auditors group read access where defaults do not |
| `setup-ssh.sh key <user> <pubkey>` | both | Authorizes a public key for a user |
| `setup-ssh.sh harden` | both | Key-only login, root login off, `AllowGroups`; validates and reloads sshd |
| `enable-service.sh` | mainapp | Enables the API at boot, starts it, waits for `/healthz` |
| `verify.sh app\|db` | both | PASS/FAIL checks of everything above; exit status 1 on any failure |

## Order of execution

PostgreSQL (on main-db) and nginx (on mainapp) must be installed first, as
described in the project report.

**mainapp**

1. `sudo bash setup-users.sh app`
2. `sudo bash setup-fs.sh app`
3. `sudo bash setup-sudoers.sh app`
4. `sudo bash setup-perms.sh app` (must come after step 3)
5. `sudo bash setup-ssh.sh key <admin-user> admin.pub` and `... key deploy deploy.pub`,
   then test both logins from a second terminal
6. Edit `/etc/tsis1linux/tsis1linux.env`, upload a release as `deploy`, point the `current` symlink at it
7. `sudo bash enable-service.sh`
8. `sudo bash setup-ssh.sh harden`
9. `sudo bash verify.sh app`, reboot, `sudo bash verify.sh app` again

**main-db**

1. `sudo bash setup-users.sh db`
2. `sudo bash setup-fs.sh db`
3. `sudo bash setup-sudoers.sh db`
4. `sudo bash setup-perms.sh db`
5. `sudo bash setup-ssh.sh key <admin-user> admin.pub`, then test the login through mainapp
6. `sudo bash setup-ssh.sh harden`
7. `sudo bash verify.sh db`, reboot, `sudo bash verify.sh db` again

## Getting the scripts onto the machines

Clone this repository on mainapp. main-db has no route to the internet by
design, so copy the scripts from your laptop through the jump host instead:

```
scp setup-*.sh verify.sh db:~/
```

Generate SSH key pairs on your laptop, never on a server:

```
ssh-keygen -t ed25519 -f ~/.ssh/tsis1-deploy -C "tsis1linux deploy bot"
```

Only the `.pub` file goes to the server. The deploy bot's private key belongs in
the CI secret store and nowhere else.

## Things worth knowing

- **Order matters for ACLs.** Reinstalling a file with `install` removes its ACL.
  `setup-sudoers.sh` reinstalls its files on every run, so run `setup-perms.sh`
  again after it.
- **SSH hardening can lock you out.** `setup-ssh.sh harden` keeps the `ubuntu`
  group allowed until you rerun it with `EXTRA_GROUPS=""`. Always test a login
  as the new user from a second terminal before hardening, and keep your
  existing session open.
- **Passwordless sudo is a deliberate trade-off.** The accounts have no
  passwords, so the SSH key is the only authentication. Anyone holding an admin
  key has root.
- **Existing files are kept.** `setup-fs.sh` never overwrites a file that
  already exists (so edited secrets survive). To change the installed systemd
  unit, edit or delete it on the machine, rerun the script, then run
  `systemctl daemon-reload`.
- **Do not commit secrets.** The env file in this repository only contains
  `CHANGE_ME` placeholders.