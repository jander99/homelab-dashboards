# homelab-dashboards

## Architecture
- Grafana Git Sync (Model A): Grafana polls this repo every 60s via GitHub PAT
- No Flux involvement. Grafana talks directly to GitHub.
- Grafana URL: https://grafana.homelab.properties
- Grafana version: 13.0.1
- Git Sync polls: main branch, dashboards/ path
- Webhook not possible (Grafana is internal MetalLB, not reachable from GitHub)

## Git Sync Initialization
Git Sync is configured via gcx CLI (one-time manual step).
Runbook: homelab repo at k3s/applications/monitoring/RUNBOOK.md
PAT: stored in SOPS secret (homelab repo, monitoring namespace) + BitWarden entry "homelab-dashboards grafana-gitsync PAT"

## Repository Rules
- NEVER commit secrets, .env files, or tokens to this repo (it is PUBLIC)
- Dashboard JSON goes in dashboards/ only
- README, .github/, and other files in repo root do NOT trigger Grafana sync
- Grafana saves create branches named grafana/<timestamp> and open PRs (auto-merge after checks)
- Human/LLM dashboard changes require manual PR review

## Dashboard Conventions
- File location: dashboards/<dashboard-slug>.json
- UIDs: set explicitly in JSON (do not rely on auto-generated UIDs — they change on re-import)
- Grafana folder: "Homelab" (do not use "General" — conflicts with kube-prometheus-stack provisioned dashboards)
- Titles: human-readable, e.g. "Homelab Overview", "Media Pipeline", "Node Health"

## Prometheus Data Sources
- Endpoint (in-cluster): http://kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090
- External: https://prometheus.homelab.properties (if accessible)
- All scrape targets confirmed active — see metrics catalog below

## Metrics Catalog (Key Sources)
### Media Stack (exportarr — 4m scrape interval)
- sonarr_episode_total, sonarr_episode_downloaded_total, sonarr_episode_missing_total, sonarr_episode_cutoff_unmet_total
- sonarr_series_total, sonarr_series_downloaded_total, sonarr_episode_quality_total{quality, weight}
- radarr_movie_total, radarr_movie_downloaded_total, radarr_movie_missing_total, radarr_movie_cutoff_unmet_total, radarr_movie_filesize_total
- prowlarr_indexer_total, prowlarr_indexer_{queries,grabs,failed_queries,failed_grabs}_total{indexer}, prowlarr_indexer_average_response_time_ms{indexer}
- {app}_queue_total{status, download_status, download_state} — for sonarr, radarr, prowlarr
- {app}_rootfolder_freespace_bytes{path} — for sonarr, radarr
- {app}_system_status — 1=up, 0=down

### Downloads
- sabnzbd_* — SABnzbd via exportarr (namespace: sabnzbd, 4m)
- qbittorrent_* — qBittorrent exporter (namespace: qbittorrent, 4m)
- gluetun_* — VPN health for both sabnzbd and qbittorrent gluetun sidecars

### Infrastructure
- node_* — node-exporter (K3s node 192.168.1.128 + Synology NAS 192.168.1.20)
- kube_* — kube-state-metrics (K3s cluster state)
- container_* — cAdvisor (per-pod resource usage)
- DCGM/GPU metrics: NOT YET available (pending homelab issue #138)
- Tdarr transcode metrics: NOT YET available (pending homelab issue #139)
- Unifi metrics: NOT YET available (pending homelab issue #140)

### DNS
- pihole_* — Pi-hole exporter (port 9617, PodMonitor, 4m)

### Availability
- probe_success — blackbox probes: tdarr, portainer, headlamp, authentik

## Dashboard Index
- dashboards/homelab-overview.json — all services, rows per category [WIP: issue #1]
- dashboards/media-pipeline.json — Sonarr/Radarr/Prowlarr/SABnzbd detail [issue #4]
- dashboards/node-health.json — K3s node + Synology [issue #5]
- dashboards/pihole-dns.json — Pi-hole DNS [issue #6]
- dashboards/tdarr-transcoding.json — Tdarr GPU pipeline [issue #7, blocked on homelab #139]
- dashboards/download-health.json — VPN + download clients [issue #8]

## Adding a Dashboard
1. Build in Grafana UI (https://grafana.homelab.properties)
2. Save → "Push to new branch" → PR opens automatically (branch: grafana/<timestamp>)
3. PR auto-merges after status checks pass
4. OR: export JSON from Grafana, save to dashboards/<slug>.json, commit to a branch, open PR for review
5. Use explicit UIDs. Use folder "Homelab". Do not edit dashboards managed by kube-prometheus-stack.

## Deletion Warning
Removing a JSON file from dashboards/ causes Grafana to DELETE that dashboard from the UI.
This is irreversible without a git revert.
