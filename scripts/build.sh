#!/bin/bash

set -e  # Exit on error

# ============================================================================
# Logging
# ============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_section() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

# ============================================================================
# Package Discovery
# ============================================================================

discover_packages() {
    local search_dir="$1"
    local whitelist="$2"
    local blacklist="$3"

    log_info "Discovering ROS packages in: $search_dir"

    local package_xml_files
    package_xml_files=$(find "$search_dir" -name "package.xml" -type f)

    if [ -z "$package_xml_files" ]; then
        log_error "No ROS packages found in $search_dir"
        exit 1
    fi

    PACKAGE_PATHS=()

    for package_xml in $package_xml_files; do
        local package_dir
        package_dir=$(dirname "$package_xml")

        # Apply whitelist filter on directory path
        if ! echo "$package_dir" | grep -qE "$whitelist"; then
            log_info "Package at '$package_dir' excluded by whitelist"
            continue
        fi

        # Apply blacklist filter on directory path
        if [ -n "$blacklist" ] && echo "$package_dir" | grep -qE "$blacklist"; then
            log_info "Package at '$package_dir' excluded by blacklist"
            continue
        fi

        log_info "Found package at: $package_dir"
        PACKAGE_PATHS+=("$package_dir")
    done

    if [ ${#PACKAGE_PATHS[@]} -eq 0 ]; then
        log_error "No packages matched the whitelist/blacklist filters"
        exit 1
    fi
}

# ============================================================================
# Workspace Build
# ============================================================================

build_workspace() {
    log_section "Building workspace with all packages"

    local workspace_src="$WORKSPACE/workspace/src"
    mkdir -p "$workspace_src"

    # Copy all packages into workspace
    log_info "Copying packages into workspace..."
    for source_dir in "${PACKAGE_PATHS[@]}"; do
        local pkg_name
        pkg_name=$(basename "$source_dir")
        log_info "  - $pkg_name"
        cp -r "$source_dir" "$workspace_src/$pkg_name"
    done

    cd "$WORKSPACE/workspace"

    # Install all dependencies
    log_info "Installing workspace dependencies..."
    rosdep install --from-paths src --ignore-src -y -r --rosdistro "$ROS_DISTRO" 2>&1 || {
        log_warn "Some dependencies could not be installed, continuing..."
    }

    # Build workspace based on ROS version
    log_info "Building workspace..."
    if [ "$ROS_VERSION" = "1" ]; then
        # ROS1: Use catkin
        # shellcheck disable=SC1090
        source /opt/ros/"$ROS_DISTRO"/setup.bash
        if ! catkin_make 2>&1; then
            log_error "Workspace build failed"
            return 1
        fi
        # shellcheck disable=SC1091
        source devel/setup.bash
    else
        # ROS2: Use colcon
        # shellcheck disable=SC1090
        source /opt/ros/"$ROS_DISTRO"/setup.bash
        if ! colcon build --symlink-install 2>&1; then
            log_error "Workspace build failed"
            return 1
        fi
        # shellcheck disable=SC1091
        source install/setup.bash
    fi

    log_info "Workspace built successfully"
    return 0
}

# ============================================================================
# Single Package Bloom
# ============================================================================

bloom_package() {
    local source_dir="$1"
    local index="$2"
    local total="$3"

    log_section "Generating debian for package $index/$total"

    local pkg_name
    pkg_name=$(basename "$source_dir")
    log_info "Package: $pkg_name"

    # Create bloom workspace for this package
    local bloom_dir="$WORKSPACE/bloom/$pkg_name"
    mkdir -p "$bloom_dir"
    cd "$bloom_dir"

    # Initialize git repo with package source
    git init -q
    cp -r "$source_dir"/* .

    # Generate debian files
    log_info "Generating debian files with bloom..."
    if ! bloom-generate rosdebian \
        --os-name ubuntu \
        --os-version "$DEBIAN_DISTRO" \
        --ros-distro "$ROS_DISTRO" 2>&1; then
        log_error "Bloom generation failed"
        return 1
    fi

    # Build debian package
    log_info "Building debian package..."
    if [ ! -d "debian" ]; then
        log_error "Debian directory not found"
        return 1
    fi

    if ! fakeroot debian/rules binary 2>&1; then
        log_error "Debian build failed"
        return 1
    fi

    # Collect .deb files
    local deb_files
    deb_files=$(find "$WORKSPACE/bloom" -maxdepth 2 -name "*.deb" -type f)

    if [ -z "$deb_files" ]; then
        log_error "No debian packages were generated"
        return 1
    fi

    log_info "Collecting debian packages..."
    for deb in $deb_files; do
        cp "$deb" "$OUTPUT_DIR/"
        log_info "Generated: $(basename "$deb")"
    done

    log_info "Successfully generated debian for $pkg_name"
    return 0
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Validate environment
    if [ -z "$ROS_DISTRO" ] || [ -z "$DEBIAN_DISTRO" ]; then
        log_error "Missing required environment variables"
        log_error "Required: ROS_DISTRO, DEBIAN_DISTRO"
        exit 1
    fi

    # Set defaults
    PACKAGES_DIR="${PACKAGES_DIR:-.}"
    PACKAGE_WHITELIST="${PACKAGE_WHITELIST:-.*}"
    PACKAGE_BLACKLIST="${PACKAGE_BLACKLIST:-}"
    WORKING_DIR="./bloom-build"

    log_section "ROS Bloom Release - Multi-Package Build"
    log_info "ROS Distro: $ROS_DISTRO"
    log_info "Debian Distro: $DEBIAN_DISTRO"
    log_info "Packages Directory: $PACKAGES_DIR"
    log_info "Whitelist Pattern: $PACKAGE_WHITELIST"
    log_info "Blacklist Pattern: $PACKAGE_BLACKLIST"

    # Setup paths
    ORIGINAL_DIR="$(pwd)"
    WORKSPACE="$ORIGINAL_DIR/$WORKING_DIR"
    OUTPUT_DIR="$WORKSPACE/output"
    mkdir -p "$WORKSPACE" "$OUTPUT_DIR"

    log_info "Working directory: $WORKSPACE"

    # Resolve search directory
    if [[ "$PACKAGES_DIR" = /* ]]; then
        SEARCH_DIR="$PACKAGES_DIR"
    else
        SEARCH_DIR="$ORIGINAL_DIR/$PACKAGES_DIR"
    fi

    if [ ! -d "$SEARCH_DIR" ]; then
        log_error "Package search directory not found: $SEARCH_DIR"
        exit 1
    fi

    # Discover packages
    discover_packages "$SEARCH_DIR" "$PACKAGE_WHITELIST" "$PACKAGE_BLACKLIST"

    log_section "Processing ${#PACKAGE_PATHS[@]} package(s)"

    # Setup git for bloom
    git config --global user.name "Bloom Release Bot"
    git config --global user.email "bloom@github-actions"

    # Initialize rosdep
    log_info "Initializing rosdep..."
    sudo rosdep init 2>&1 || log_warn "rosdep already initialized"

    log_info "Updating rosdep..."
    if ! rosdep update 2>&1; then
        log_error "rosdep update failed"
        exit 1
    fi

    log_info "Verifying rosdep sources..."
    if [ ! -f "/etc/ros/rosdep/sources.list.d/20-default.list" ]; then
        log_error "rosdep sources not found after initialization"
        exit 1
    fi

    # Detect ROS version
    if [[ "$ROS_DISTRO" =~ ^(melodic|noetic)$ ]]; then
        ROS_VERSION="1"
        log_info "Detected ROS 1"
    else
        ROS_VERSION="2"
        log_info "Detected ROS 2"
    fi

    # Build workspace with all packages together
    if ! build_workspace; then
        log_error "Workspace build failed"
        exit 1
    fi

    # Generate debian packages for each package
    local bloom_success=0
    local bloom_failed=0

    for i in "${!PACKAGE_PATHS[@]}"; do
        local source_dir="${PACKAGE_PATHS[$i]}"

        if bloom_package "$source_dir" "$((i+1))" "${#PACKAGE_PATHS[@]}"; then
            bloom_success=$((bloom_success + 1))
        else
            bloom_failed=$((bloom_failed + 1))
        fi
    done

    # Summary
    log_section "Build Summary"
    log_info "Total packages: ${#PACKAGE_PATHS[@]}"
    log_info "Successful: $bloom_success"
    log_info "Failed: $bloom_failed"

    # Check for output
    local all_deb_files
    all_deb_files=$(find "$OUTPUT_DIR" -name "*.deb" -type f)

    if [ -z "$all_deb_files" ]; then
        log_error "No debian packages were generated!"
        exit 1
    fi

    log_section "Generated Debian Packages"
    while IFS= read -r deb; do
        log_info "  - $(basename "$deb")"
    done < <(find "$OUTPUT_DIR" -name "*.deb" -type f)

    if [ $bloom_failed -gt 0 ]; then
        log_warn "Some packages failed to build"
        exit 1
    fi

    log_info "All builds completed successfully!"
}

# Run main
main
