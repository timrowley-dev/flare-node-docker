# Flare Node Docker Compose Setup

## 📋 **Table of Contents**

- [Quick Setup Steps](#-quick-setup-steps)
- [Files Structure](#files-structure)
- [Configuration Options](#configuration-options)
- [Common Operations](#common-operations)
- [Validator Setup](#validator-setup)
- [Node Updates](#node-updates)
- [Troubleshooting](#troubleshooting)
- [Hardware Requirements](#-hardware-requirements)
- [Helpful Links](#-helpful-links)

### ✅ **Fully Supported Features**

- **Network Support**: flare, coston, costwo, songbird
- **Node Types**: Observer and Validator nodes
- **Config templates**: Public and private API profiles. Validators always use a web3-only template
- **Configuration Management**: Automatic config.json selection
- **Volume Management**: Persistent data, logs, and staking directories
- **Health Monitoring**: Built-in health checks
- **Bootstrap Endpoints**: Auto-configured per network

### 📋 **Quick Setup Steps**

1. **(Optional) Install Docker if not present**:

   ```bash
   # Automated Docker installation using official repository
   ./install-docker.sh
   ```

2. **Ensure database directory exists**:

   ```bash
   # Create your database directory (adjust path as needed)
   # We recommend using a dedicated disk mounted to the host machine
   # This isolates the database and makes backups easier
   sudo mkdir -p /mnt/disks/db
   ```

3. **Run setup with interactive config selection**:

   ```bash
   ./setup.sh
   ```

   The script will:

   - Create .env file from template
   - Create `/opt/flare/` directories
   - Ask whether this node is an observer or a validator
   - For an observer, ask which template to use (public or private). Validators always use the web3-only template
   - Ask for an image tag when the default is `go-flare:latest`. Pass `--tag go-flare:v1.15.1` to skip the prompt
   - Copy the selected config to `/opt/flare/configs/config.json`
   - For a validator, keep the existing staking identity or refuse to start until those files are in place

4. **Edit configurations**:

   ```bash
   # Edit .env with your settings (network, version, db path, etc.)
   nano .env

   # Review config in /opt/flare/configs and optionally modify to requirements.
   ```

5. **Start the node**:

   ```bash
   docker compose up -d
   ```

6. **Check status**:
   ```bash
   ./health-check.sh
   ```

## Files Structure

```
├── docker compose.yaml      # Main container configuration
├── env.example             # Environment template
├── install-docker.sh       # Docker installation script
├── setup.sh               # Setup script (replaces install functionality)
├── update.sh              # Automated update script
├── staking-identity.sh    # Shared staking-file salvage used by setup and update
├── health-check.sh         # Health monitoring (replaces --status)
├── configs/               # Local config templates
│   ├── config.json.public      # Public node config template
│   ├── config.json.private     # Private node config template
│   └── config.json.validator   # Validator config template (web3 only)
└── /opt/flare/            # Production directories (created by setup.sh)
    ├── configs/
    │   └── config.json        # Active config (copied from template)
    ├── logs/              # Node logs
    └── staking/           # Validator certificates
```

## Configuration Options

### Environment Variables (.env file)

| Variable          | Description             | Example                                 |
| ----------------- | ----------------------- | --------------------------------------- |
| `NETWORK`         | Network to connect to   | `flare`, `coston`, `costwo`, `songbird` |
| `NODE_TAG`              | Docker image tag. Default `go-flare:latest` does not include Helicon. Pass `--tag` at install | `go-flare:v1.15.1` |
| `DB_DIR`                | Database directory path | `/mnt/disks/db`                         |
| `NODE_TYPE`             | Node type               | `observer`, `validator`                 |
| `HTTP_HOST`             | In-container RPC bind. Leave at `0.0.0.0` | `0.0.0.0`                        |
| `HTTP_PUBLISH_HOST`     | Host address for port 9650. Falls back to `HTTP_HOST` | `127.0.0.1`            |
| `STAKING_PUBLISH_HOST`  | Host address for port 9651. Falls back to `HTTP_HOST` | `0.0.0.0`              |
| `HTTP_ALLOWED_HOSTS`    | RPC hostname allow list | `*`                                     |
| `EXTRA_ARGUMENTS`       | Additional node args. Validator staking flags are added by setup | `--index-enabled=1` |
| `BOOTSTRAP_ENDPOINT`    | Optional override of the image bootstrap URL. Leave unset to use the image default | `https://flare-bootstrap.flare.network/ext/info` |

### Common Operations

```bash
# Install Docker (if needed)
./install-docker.sh

# Interactive setup (choose config type and, for a new install, the image tag)
./setup.sh

# Non-interactive setup
./setup.sh --tag go-flare:v1.15.1 observer public    # Observer with the public template
./setup.sh --tag go-flare:v1.15.1 observer private   # Observer with the private template
./setup.sh --tag go-flare:v1.15.1 validator          # Existing validator; staking files must already be present
./setup.sh --new-validator --tag go-flare:v1.15.1 validator  # Create a new staking identity on first start

# After pulling Compose changes, run ./setup.sh or ./update.sh before the first up
# so validator staking flags are written before the container is recreated.

# Start node
docker compose up -d

# Check status
./health-check.sh
docker compose ps

# View logs
docker compose logs -f

# Stop node
docker compose down

# Restart node
docker compose restart

# Upgrade node (interactive - shows latest versions)
./update.sh

# Upgrade node. Use the script so staking flags are in place before recreate.
./update.sh go-flare:v1.15.1
```

## Validator Setup

`staker.crt`, `staker.key`, and `signer.key` are the node identity. Setup writes `NODE_TYPE=validator` and the staking file flags only after those files are safe. The flags point the node at `/opt/flare/staking` (mounted at `/app/staking`). `staker.key` and `signer.key` are kept at mode `600`.

### New validator

```bash
./setup.sh --new-validator --tag go-flare:v1.15.1 validator
docker compose up -d
```

The first start creates the three files in `/opt/flare/staking`. Back them up before moving the node.

### Restore an existing validator on a new machine

1. On the old machine, run `./update.sh` or `./setup.sh` so the three files are copied out of the container into `/opt/flare/staking` if they are not already there.
2. Copy `staker.crt`, `staker.key`, and `signer.key` to `/opt/flare/staking` on the new machine.
3. Run `./setup.sh --tag go-flare:v1.15.1 validator`. Setup leaves the file contents alone.
4. Start only after that command finishes: `docker compose up -d`.

`./setup.sh validator` with an empty staking directory does not create a new identity. Pass `--new-validator` only when this node has never had one.

To publish RPC only on this machine and still accept peer connections, set `HTTP_HOST=0.0.0.0`, `HTTP_PUBLISH_HOST=127.0.0.1`, and `STAKING_PUBLISH_HOST=0.0.0.0`.

## Node Updates

### Automated Update Process

Use the `update.sh` script to automatically upgrade your node:

```bash
# Interactive mode - shows latest 5 version tags from Docker Hub
./update.sh

# Direct update to specific version
./update.sh go-flare:v1.15.1
```

**Interactive Mode:**
When run without arguments, the script fetches the latest 5 version tags from [Docker Hub](https://hub.docker.com/r/flarefoundation/go-flare/tags) and presents a menu:

```
Available latest version tags:

  1) go-flare:v1.15.1
  2) go-flare:v1.14.2
  3) go-flare:v1.14.0
  4) go-flare:v1.13.0
  5) go-flare:v1.12.0
  6) Custom version (enter manually)
  0) Cancel

Select version (0-6):
```

**The script will:**

1. Show current vs new version and ask for confirmation
2. Keep existing staking files. A validator with those files still missing is not recreated. Missing staking path flags are added
3. Update `NODE_TAG` in `.env` file (creates `.env.backup`)
4. Pull the new image (`docker compose pull`) while the current container keeps running
5. Recreate with the new image (`docker compose up -d`) only after the pull succeeds
6. Verify the update and show node version
7. Restore `.env` and leave the running container in place if the pull fails. Restore `.env` and start the previous version if the new container does not stay up

### Manual Update Process

Use `./update.sh` so the staking flags are written before Compose recreates the container. After pulling changes to this repository, run `./update.sh` or `./setup.sh` before the first `docker compose up -d`.

```bash
./update.sh go-flare:v1.15.1
```

## Troubleshooting

### Common Issues

1. **Permission errors**: Run `./setup.sh` to fix permissions
2. **Container won't start**: Check `docker compose logs` for errors
3. **Connection refused**: Ensure ports 9650/9651 are not in use
4. **Disk space**: Archival nodes require significant storage

### Health Check Failures

```bash
# Check container status
docker compose ps

# View recent logs
docker compose logs --tail=50

# Restart if needed
docker compose restart
```

## 💾 **Hardware Requirements** (September 2025)

### **Flare (Mainnet)**

| Component             | Requirement                     |
| --------------------- | ------------------------------- |
| CPU                   | 4 cores                         |
| RAM                   | 16 GB                           |
| Disk space (pruned)   | 900 GB SSD                      |
| Disk space (archival) | 3.5 TB SSD                      |
| Disk growth           | 30 GB/month                     |
| Disk speed            | 1200 MB/s read + 600 MB/s write |

### **Coston2 (Flare Testnet)**

| Component             | Requirement                     |
| --------------------- | ------------------------------- |
| CPU                   | 4 cores                         |
| RAM                   | 16 GB                           |
| Disk space (pruned)   | 150 GB SSD                      |
| Disk space (archival) | 1 TB SSD                        |
| Disk growth           | 5 GB/month                      |
| Disk speed            | 1200 MB/s read + 600 MB/s write |

### **Songbird**

| Component             | Requirement                     |
| --------------------- | ------------------------------- |
| CPU                   | 4 cores                         |
| RAM                   | 16 GB                           |
| Disk space (pruned)   | 2 TB SSD                        |
| Disk space (archival) | 8 TB SSD                        |
| Disk growth           | 120 GB/month                    |
| Disk speed            | 1200 MB/s read + 600 MB/s write |

### **Coston (Songbird Testnet)**

| Component             | Requirement                     |
| --------------------- | ------------------------------- |
| CPU                   | 4 cores                         |
| RAM                   | 16 GB                           |
| Disk space (pruned)   | 150 GB SSD                      |
| Disk space (archival) | 1 TB SSD                        |
| Disk growth           | 11 GB/month                     |
| Disk speed            | 1200 MB/s read + 600 MB/s write |

**⚠️ Important Notes:**

- **SSD Required**: Traditional HDDs are too slow for blockchain operations
- **Disk Growth**: Plan for continuous growth over time
- **Archival Nodes**: Require significantly more storage but provide full historical data
- **Hardware**: You may need to adjust CPU/RAM depending on node usage

### 🔗 **Helpful Links**

| Resource                | Link                                                                            |
| ----------------------- | ------------------------------------------------------------------------------- |
| Official Flare Docs     | [dev.flare.network/run-node](https://dev.flare.network/run-node)                |
| Flare Docker Repository | [Docker Hub](https://hub.docker.com/r/flarefoundation/go-flare/)                |
| Node Config Flags       | [Avalanche Docs](https://build.avax.network/docs/nodes/configure/configs-flags) |
| C-Chain Configurations  | [Avalanche Docs](https://build.avax.network/docs/nodes/chain-configs/c-chain)   |
