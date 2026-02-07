# WSO2 API Manager 3.0.0 – Distributed Setup

This project sets up a local WSO2 APIM 3.0.0 **distributed** environment (Key Manager, Traffic Manager, Publisher, Devportal, Gateway) using prepared component packs and a MySQL Docker container.


## Scripts

### 1) Setup components + MySQL

Prepare component packs and start MySQL:
```bash
# Seed DB + setup components
./setup.sh seed /path/to/updated/wso2am-3.0.0

# Skip DB seeding + setup components
./setup.sh skip /path/to/updated/wso2am-3.0.0
```

seed / skip applies only to database seeding.

Prepared components will be created under:

./components/key_manager

./components/traffic_manager

./components/publisher

./components/devportal

./components/gateway


2) Start profiles (sequential)

Start all profiles one-by-one in the correct order:

./start.sh


Manual startup order (if starting by hand from each component’s bin/ directory):

sh wso2server.sh -Dprofile=api-key-manager
sh wso2server.sh -Dprofile=traffic-manager
sh wso2server.sh -Dprofile=api-publisher
sh wso2server.sh -Dprofile=api-devportal
sh wso2server.sh -Dprofile=gateway-worker


Wait until each server fully starts before starting the next one.

3) Stop profiles

Stop all profiles:

./stop.sh


Stop all profiles and stop/remove Docker containers + volumes (clean slate):

./stop.sh --clean

Component Ports
Component	Profile	Port Offset	HTTPS Port (Servlet)	Other Ports
Traffic Manager	traffic-manager	0	9443	9611, 9711
Key Manager	api-key-manager	1	9444	Offset-based
Publisher	api-publisher	2	9445	9443 (internal)
Gateway	gateway-worker	3	9446	8283, 8246
Developer Portal	api-devportal	4	9447	Same as Publisher
Access URLs
Component	URL
Traffic Manager	https://localhost:9443/carbon

Key Manager	https://localhost:9444/carbon

Publisher	https://localhost:9445/publisher

Gateway	https://localhost:9446/services

Developer Portal	https://localhost:9447/devportal
Logs

Startup script logs are written to:

./logs/<component>.log

Example:

tail -f ./logs/key_manager.log
