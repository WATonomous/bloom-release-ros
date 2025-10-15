# bloom-release-ros

A GitHub Action for automatically building and packaging ROS 2 packages into Debian packages using [bloom](https://wiki.ros.org/bloom).

**IMPORTANT** This action does not support End of Life ROS distributions.

## Features

- Automatically discovers and builds all ROS 2 packages in your repository
- Filter packages using whitelist/blacklist regex patterns
- Supports ROS 2 (Humble, Jazzy, Kilted, Rolling)
- Outputs ready-to-deploy .deb files

## Quick Start

```yaml
name: Build ROS Packages

on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4

      - uses: watonomous/bloom-release-ros@v0.1.0
        with:
          ros_distro: 'humble'
          debian_distro: 'jammy'
          packages_dir: '.'  # Optional: directory to search for packages
          package_whitelist: '.*'  # Optional: regex to whitelist packages
          package_blacklist: ''  # Optional: regex to blacklist packages
          artifact_name: '' # Optional: name of artifacts produced
```

Artifacts are automatically uploaded as `bloom-debian-packages-{distro}-{job}-{run_id}` and can be downloaded from the Actions tab.

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `ros_distro` | ROS 2 distribution (humble, jazzy, kilted, rolling) | Yes | - |
| `debian_distro` | Debian/Ubuntu distribution (jammy, noble) | Yes | - |
| `packages_dir` | Directory to search for ROS packages | No | `.` |
| `package_whitelist` | Regex to whitelist package names | No | `.*` |
| `package_blacklist` | Regex to blacklist package names | No | `''` |
| `artifact_name` | Custom artifact name (avoids conflicts in parallel jobs) | No | `bloom-debian-packages-{distro}-{job}-{run_id}` |

## Filtering Packages

```yaml
# Build only packages starting with "myproject_"
package_whitelist: '^myproject_.*'

# Exclude test packages
package_blacklist: '.*_test$'

# Combine filters
package_whitelist: '^myproject_.*'
package_blacklist: '.*_(test|sim)$'
```

## How It Works

1. Searches for all `package.xml` files in `packages_dir`
2. Filters packages using whitelist/blacklist patterns
3. Builds all packages together in a workspace using colcon (handles inter-package dependencies)
4. For each package: runs bloom-generate and builds .deb
5. Collects all .deb files into output directory

## Requirements

- Must checkout repository with `actions/checkout@v4` first
- Each package needs valid `package.xml`
- Dependencies should be available via apt or rosdep

## Troubleshooting

**Bloom generation fails**: Ensure `package.xml` has all required fields (name, version, description, maintainer, license)

**Build dependencies not found**: Ensure all dependencies are properly declared in `package.xml` and available via rosdep

## License

Apache 2.0 License - see [LICENSE](LICENSE)
