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
# Single Package Build
# ============================================================================

build_package() {
    local source_dir="$1"
    local index="$2"
    local total="$3"

    log_section "Building package $index/$total"
    log_info "Source: $source_dir"

    # Create package-specific workspace (use basename of source dir)
    local pkg_name
    pkg_name=$(basename "$source_dir")
    local pkg_workspace="$WORKSPACE/packages/$pkg_name"
    mkdir -p "$pkg_workspace"

    # Copy source
    local repo_dir="$pkg_workspace/source"
    rm -rf "$repo_dir"
    mkdir -p "$repo_dir"
    cp -r "$source_dir"/* "$repo_dir"/
    cd "$repo_dir"

    # Create bloom workspace
    local bloom_dir="$pkg_workspace/bloom"
    mkdir -p "$bloom_dir"
    cd "$bloom_dir"

    local release_repo="$bloom_dir/release"
    mkdir -p "$release_repo"
    cd "$release_repo"
    git init -q
    cp -r "$repo_dir"/* .

    # Generate debian files
    log_info "Generating debian files with bloom..."
    if ! bloom-generate rosdebian \
        --os-name ubuntu \
        --os-version "$DEBIAN_DISTRO" \
        --ros-distro "$ROS_DISTRO" 2>&1; then
        log_error "Bloom generation failed"
        return 1
    fi

    # Install dependencies
    log_info "Installing build dependencies..."
    if [ -f "package.xml" ]; then
        rosdep install --from-paths . --ignore-src -y -r --rosdistro "$ROS_DISTRO" 2>&1 || {
            log_warn "Some dependencies could not be installed, continuing..."
        }
    fi

    # Build debian package
    log_info "Building debian package..."
    if [ ! -d "debian" ]; then
        log_error "Debian directory not found"
        return 1
    fi

    if ! fakeroot debian/rules binary 2>&1; then
        log_error "Build failed"
        return 1
    fi

    # Collect .deb files
    local deb_files
    deb_files=$(find "$bloom_dir" -name "*.deb" -type f)

    if [ -z "$deb_files" ]; then
        log_error "No debian packages were generated"
        return 1
    fi

    log_info "Collecting debian packages..."
    for deb in $deb_files; do
        cp "$deb" "$OUTPUT_DIR/"
        log_info "Generated: $(basename $deb)"
    done

    log_info "Successfully built package"
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

    log_section "Building ${#PACKAGE_PATHS[@]} package(s)"

    # Setup git for bloom
    git config --global user.name "Bloom Release Bot"
    git config --global user.email "bloom@github-actions"

    # Build all packages
    local build_success=0
    local build_failed=0

    for i in "${!PACKAGE_PATHS[@]}"; do
        local source_dir="${PACKAGE_PATHS[$i]}"

        if build_package "$source_dir" "$((i+1))" "${#PACKAGE_PATHS[@]}"; then
            build_success=$((build_success + 1))
        else
            build_failed=$((build_failed + 1))
        fi
    done

    # Summary
    log_section "Build Summary"
    log_info "Total packages: ${#PACKAGE_PATHS[@]}"
    log_info "Successful: $build_success"
    log_info "Failed: $build_failed"

    # Check for output
    local all_deb_files
    all_deb_files=$(find "$OUTPUT_DIR" -name "*.deb" -type f)

    if [ -z "$all_deb_files" ]; then
        log_error "No debian packages were generated!"
        exit 1
    fi

    log_section "Generated Debian Packages"
    for deb in $(find "$OUTPUT_DIR" -name "*.deb" -type f); do
        log_info "  - $(basename $deb)"
    done

    if [ $build_failed -gt 0 ]; then
        log_warn "Some packages failed to build"
        exit 1
    fi

    log_info "All builds completed successfully!"
}

# Run main
main
