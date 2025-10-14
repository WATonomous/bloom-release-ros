# bloom-release-ros

A GitHub Action for automatically building and packaging ROS packages into Debian packages using [bloom](https://wiki.ros.org/bloom).

## Features

- Automatically discovers and builds all ROS packages in your repository
- Filter packages using whitelist/blacklist regex patterns
- Supports ROS 1 (Noetic) and ROS 2 (Humble, Iron, Jazzy, etc.)
- Outputs ready-to-deploy .deb files

## Quick Start

```yaml
name: Build ROS Packages

on:
  push:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-20.04
    steps:
      - uses: actions/checkout@v4

      - uses: watonomous/bloom-release-ros@v1
        with:
          ros_distro: 'noetic'
          debian_distro: 'focal'
          packages_dir: '.'  # Optional: directory to search for packages
          package_whitelist: '.*'  # Optional: regex to whitelist packages
          package_blacklist: ''  # Optional: regex to blacklist packages
```

Artifacts are automatically uploaded as `ros-debian-packages-{distro}` and can be downloaded from the Actions tab.

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `ros_distro` | ROS distribution (noetic, humble, iron, jazzy) | Yes | - |
| `debian_distro` | Debian/Ubuntu distribution (focal, jammy, noble) | Yes | - |
| `packages_dir` | Directory to search for ROS packages | No | `.` |
| `package_whitelist` | Regex to whitelist package names | No | `.*` |
| `package_blacklist` | Regex to blacklist package names | No | `''` |

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
3. For each package: runs bloom-generate, installs dependencies, builds .deb
4. Collects all .deb files into output directory

## Requirements

- Must checkout repository with `actions/checkout@v4` first
- Each package needs valid `package.xml`
- Dependencies should be available via apt or rosdep

## Troubleshooting

**Bloom generation fails**: Ensure `package.xml` has all required fields (name, version, description, maintainer, license)

**Build dependencies not found**: Ensure all dependencies are properly declared in `package.xml` and available via rosdep

## License

Apache 2.0 License - see [LICENSE](LICENSE)
