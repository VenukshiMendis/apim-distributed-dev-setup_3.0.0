# WSO2 API Manager 3.0.0 – Distributed Setup

This repository helps you set up a **local WSO2 API Manager 3.0.0 distributed deployment** using prepared component packs and a **MySQL Docker** container.

Components included:
- Key Manager
- Traffic Manager
- Publisher
- Developer Portal
- Gateway


## Prerequisites

- **WSO2 APIM 3.0.0 updated pack** (path required when running `setup.sh`)
- **Docker** (for MySQL)
- **Java** (compatible with APIM 3.0.0)


## Repository Structure

After setup, prepared components will be created under:

- `./components/key_manager`
- `./components/traffic_manager`
- `./components/publisher`
- `./components/devportal`
- `./components/gateway`

Logs will be written under:

- `./logs/`

## Scripts

### 1) Setup components + MySQL

Prepare component packs and start MySQL.

**Seed DB + setup components**
```bash
./setup.sh seed /path/to/updated/wso2am-3.0.0
``` 
**Skip DB seeding + setup components** 

Use this option if the database is already populated and you want to skip the database seeding step.
```bash
./setup.sh skip /path/to/updated/wso2am-3.0.0
```

### 2) Start profiles (sequential)


You can start the servers using **either** the script **or** the manual commands below.

#### Option A: Start using the script (recommended)
Starts all profiles **one-by-one** in the correct order:
```bash
./start.sh
```
#### Option B: Start manually 

If you prefer to start each component yourself, go into each component’s bin/ directory and run the following in **order**

```bash
sh wso2server.sh -Dprofile=api-key-manager
sh wso2server.sh -Dprofile=traffic-manager
sh wso2server.sh -Dprofile=api-publisher
sh wso2server.sh -Dprofile=api-devportal
sh wso2server.sh -Dprofile=gateway-worker
```

Note: Wait until each server fully starts before starting the next one.

### 3) Stop profiles

Stop all profiles:

```bash
./stop.sh
```

Stop all profiles and stop/remove Docker containers + volumes (clean slate):

```bash
./stop.sh --clean
``` 
---

### Component Ports

| Component         | Profile           | Port Offset | HTTPS Port (Servlet) | Other Ports     |
|------------------|-------------------|------------:|----------------------:|-----------------|
| Traffic Manager  | traffic-manager   | 0           | 9443                  | 9611, 9711      |
| Key Manager      | api-key-manager   | 1           | 9444                  | -               |
| Publisher        | api-publisher     | 2           | 9445                  | -               |
| Gateway          | gateway-worker    | 3           | 9446                  | 8283, 8246      |
| Developer Portal | api-devportal     | 4           | 9447                  | -               |


### Access URLs 

| Component         | URL                           |
|------------------|-------------------------------|
| Carbon Portal  | https://localhost:9443/carbon |
| Admin Portal      | https://localhost:9445/admin |
| Publisher        | https://localhost:9445/publisher |
| Developer Portal         | https://localhost:9447/devportal |
