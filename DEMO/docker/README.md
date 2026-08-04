# SQL Server 2025 Full-Text and PolyBase demo image

English | [繁體中文](README.zh-TW.md)

This is the official image-based path for the local features required by the
DP-800 demos. No SQL Server environment variable installs or enables Full-Text
Search (FTS) or PolyBase after a container has been created; use this custom
image instead.

Build the image:

```powershell
pwsh -NoProfile -File DEMO/docker/Build-DemoImage.ps1
```

To build and start a temporary, isolated probe, provide `DP800_SQL_PASSWORD` in
the current process or enter it at the secure prompt. An optional `-ProbePort`
selects the host port; without it, the script selects a free loopback port.

```powershell
pwsh -NoProfile -File DEMO/docker/Build-DemoImage.ps1 -RunProbe -ProbePort 11433
```

The probe is named `dp800-sql2025-feature-probe`, publishes a non-1433 port,
and is separate from `mssql2025`. Validate it with `docker exec` and `sqlcmd`,
then remove **only** the probe:

```powershell
docker rm -f dp800-sql2025-feature-probe
```

The normal local demo path remains the externally managed `mssql2025` container
at `127.0.0.1:1433`; use the existing `DEMO/bootstrap` and module scripts
there. Do not add volumes to, or attempt an in-place package installation on,
the current container. Replacing it with this image requires a planned database
backup and data migration because a new container has no data from the existing
one.
