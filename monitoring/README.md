# Monitoring Configuration

This directory contains reviewable monitoring configuration and a validator that
produces a checksummed bundle. It does **not** deploy dashboards or alerts to a
cloud provider.

## Directory layout

```text
monitoring/
├── alerts/security/main.json
├── dashboards/infrastructure/main.json
├── logging/infrastructure/config.json
├── init-monitoring.sh
└── update-monitoring.sh
```

The configuration is intentionally limited to the files that currently exist.
There are no populated security/cost dashboards or infrastructure alert sets yet.

## Usage

```bash
# Validate JSON and write monitoring/generated/monitoring-manifest-<env>.json
./monitoring/init-monitoring.sh -e production

# Rebuild and show which files changed since the previous manifest
./monitoring/update-monitoring.sh -e production
```

The manifest records each file path and SHA-256 digest plus an environment label.
`monitoring/generated/` is git-ignored.

## What the scripts verify

- Every monitoring JSON file parses successfully.
- A manifest can be generated atomically.
- On update, additions, removals, and digest changes are reported.

## Limitations

- No cloud API calls, dashboard imports, or alert deployment occur.
- The JSON files are provider-neutral configuration evidence, not validated
  against a specific CloudWatch/Azure Monitor/Cloud Monitoring schema.
- Applying a bundle to a backend of record requires a separate reviewed
  integration.
