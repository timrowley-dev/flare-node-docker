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

### ✅ **Fully Supported Features**

- **Network Support**: flare, coston, costwo, songbird
- **Node Types**: Observer and Validator nodes
- **Archival Mode**: Configurable pruning (archival nodes supported)
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
   - Let you choose configuration type (observer/validator/archival)
   - Copy the selected config to `/opt/flare/configs/config.json`

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
├── docker-compose.yaml      # Main container configuration
├── env.example             # Environment template
├── install-docker.sh       # Docker installation script
├── setup.sh               # Setup script (replaces install functionality)
├── update.sh              # Automated update script
├── health-check.sh         # Health monitoring (replaces --status)
├── configs/               # Local config templates
│   ├── config.json.observer    # Observer node config template
│   ├── config.json.validator   # Validator node config template
│   └── config.json.archival    # Archival node config template
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
| `NODE_TAG`        | Docker image version    | `go-flare:v1.11.0`                      |
| `DB_DIR`          | Database directory path | `/mnt/disks/db`                         |
| `NODE_TYPE`       | Node type               | `observer`, `validator`                 |
| `HTTP_HOST`       | API bind address        | `0.0.0.0`                               |
| `EXTRA_ARGUMENTS` | Additional node args    | `--http-allowed-hosts="*"`              |

### Common Operations

```bash
# Install Docker (if needed)
./install-docker.sh

# Interactive setup (choose config type)
./setup.sh

# Non-interactive setup (specify config type)
./setup.sh 1  # Observer
./setup.sh 2  # Validator
./setup.sh 3  # Archival

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

# Upgrade node (direct)
./update.sh go-flare:v1.11.1

# Upgrade node (manual)
# Update .env variable NODE_TAG with latest tag
docker compose pull
docker compose down && docker compose up -d
```

## Validator Setup

For validator nodes:

1. Run setup and select option 2 (validator): `./setup.sh`
2. Edit `.env` file: set `NODE_TYPE=validator` and other configuration
3. Place your certificates in `/opt/flare/staking/` (if new validator these will be generated for you):
   - `staker.crt` (TLS certificate)
   - `staker.key` (TLS private key)
   - `signer.key` (Staking signer key)
4. Add staking arguments to `EXTRA_ARGUMENTS` in `.env`:
   ```bash
   EXTRA_ARGUMENTS="--staking-tls-cert-file=/app/staking/staker.crt --staking-tls-key-file=/app/staking/staker.key --staking-signer-key-file=/app/staking/signer.key"
   ```
5. Start: `docker compose up -d`

## Node Updates

### Automated Update Process

Use the `update.sh` script to automatically upgrade your node:

```bash
# Interactive mode - shows latest 5 version tags from Docker Hub
./update.sh

# Direct update to specific version
./update.sh go-flare:v1.11.1
```

**Interactive Mode:**
When run without arguments, the script fetches the latest 5 version tags from [Docker Hub](https://hub.docker.com/r/flarefoundation/go-flare/tags) and presents a menu:

```
Available latest version tags:

  1) go-flare:v1.11.0
  2) go-flare:v1.10.9
  3) go-flare:v1.10.8
  4) go-flare:v1.10.7
  5) go-flare:v1.10.6
  6) Custom version (enter manually)
  0) Cancel

Select version (0-6):
```

**The script will:**

1. Show current vs new version and ask for confirmation
2. Update `NODE_TAG` in `.env` file (creates `.env.backup`)
3. Stop the current container (`docker compose down`)
4. Pull the new image (`docker compose pull`)
5. Start with new version (`docker compose up -d`)
6. Verify the update and show node version
7. **Auto-rollback** if anything fails

### Manual Update Process

If you prefer manual control:

```bash
# Edit .env file to update NODE_TAG
nano .env

# Pull new image and restart
docker compose pull
docker compose down && docker compose up -d
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
