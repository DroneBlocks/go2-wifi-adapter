#!/bin/sh
# prepare-offline.sh
# Run this first on a machine with internet to gather all needed files

prepare_offline() {
    # Check we're not running as root (to save files in user-accessible location)
    if [ "$(id -u)" = "0" ]; then
        echo "Please run this script as a normal user, not as root"
        exit 1
    fi

    # Create directory structure
    SAVE_DIR="ac1l_offline_files"
    mkdir -p "$SAVE_DIR/debs"
    cd "$SAVE_DIR" || exit 1

    # Download the driver
    echo "Downloading driver package..."
    if command -v wget >/dev/null; then
        wget --no-check-certificate -nv "https://linux.brostrend.com/rtl88x2bu-dkms.deb" -O debs/rtl88x2bu-dkms.deb
    elif command -v curl >/dev/null; then
        curl --insecure "https://linux.brostrend.com/rtl88x2bu-dkms.deb" -o debs/rtl88x2bu-dkms.deb
    else
        echo "Please install wget or curl"
        exit 1
    fi

    # Download dependencies based on detected package manager
    if command -v apt-get >/dev/null; then
        echo "Detected Debian/Ubuntu system"
        
        # Create base package list
        PKG_LIST="bc dkms libc6-dev linux-libc-dev"
        
        # Add kernel headers package
        KERNEL_VERSION=$(uname -r)
        HEADER_PKG=$(dpkg -l 'linux-image-*' | awk '/^ii/ { print $2 }' | sed 's/image/headers/')
        if [ -n "$HEADER_PKG" ]; then
            PKG_LIST="$PKG_LIST $HEADER_PKG"
        fi
        
        echo "Base package list: $PKG_LIST"
        
        # Get exact list of packages that would be installed
        echo "Determining required packages..."
        REQUIRED_PKGS=$(apt-get install --simulate $PKG_LIST 2>&1 | \
            grep ^Inst | cut -d ' ' -f 2 | sort -u)
        
        if [ -z "$REQUIRED_PKGS" ]; then
            echo "No new packages need to be installed. Dependencies are already satisfied."
            # Still download the base packages for safety
            REQUIRED_PKGS="$PKG_LIST"
        fi
        
        echo "Downloading packages:"
        echo "$REQUIRED_PKGS" | tr ' ' '\n'
        
        # Download the packages
        cd debs || exit 1
        for pkg in $REQUIRED_PKGS; do
            echo "Downloading: $pkg"
            apt-get download "$pkg"
        done
        
        # Also download the driver dependencies
        echo "Checking driver package dependencies..."
        DRIVER_DEPS=$(dpkg-deb -f rtl88x2bu-dkms.deb Depends | tr ',' '\n' | \
            sed -e 's/([^)]*)//g' -e 's/^\s*//' -e 's/\s*$//' | \
            grep -v '^$' || true)
        
        if [ -n "$DRIVER_DEPS" ]; then
            echo "Downloading driver dependencies:"
            echo "$DRIVER_DEPS" | tr ' ' '\n'
            for dep in $DRIVER_DEPS; do
                # Skip already downloaded packages
                if ! [ -f "${dep}_"* ]; then
                    echo "Downloading: $dep"
                    apt-get download "$dep"
                fi
            done
        fi
        
    elif command -v dnf >/dev/null; then
        echo "Detected Fedora/RHEL system"
        PKG_LIST="bc dkms kernel-devel-$(uname -r)"
        cd debs || exit 1
        dnf download --resolve $PKG_LIST
    elif command -v yum >/dev/null; then
        echo "Detected older RHEL/CentOS system"
        PKG_LIST="bc dkms kernel-devel-$(uname -r)"
        cd debs || exit 1
        yum install --downloadonly --downloaddir=. $PKG_LIST
    else
        echo "Unsupported distribution"
        exit 1
    fi

    cd ..

    # Create the offline installer script
    cat > install-offline.sh << 'EOF'
#!/bin/sh
# Offline installer for BrosTrend AC1L (new version) WiFi adapter

bold() {
    if [ "$_PRINTBOLD_FIRST_TIME" != 1 ]; then
        _PRINTBOLD_FIRST_TIME=1
        _BOLD_FACE=$(tput bold 2>/dev/null) || true
        _NORMAL_FACE=$(tput sgr0 2>/dev/null) || true
    fi
    printf "%s\n" "${_BOLD_FACE}$*${_NORMAL_FACE}"
}

die() {
    bold "$@" >&2
    exit 1
}

install_packages() {
    bold "Installing prerequisite packages"
    cd debs || die "Cannot find debs directory"
    
    if command -v dpkg >/dev/null; then
        # For Debian/Ubuntu
        bold "Installing Debian packages..."
        # First pass: try to install everything, ignore errors but show output
        dpkg -i *.deb || true
        # Second pass: retry now that dependencies might be satisfied
        bold "Retrying package installation to resolve dependencies..."
        dpkg -i *.deb || die "Package installation failed"
        
        # Show package status
        bold "Installed package status:"
        dpkg -l bc dkms libc6-dev linux-libc-dev linux-headers-* | grep ^ii || true
    elif command -v rpm >/dev/null; then
        # For RHEL/Fedora
        rpm -ivv *.rpm || die "Package installation failed"
    else
        die "No supported package manager found"
    fi
    cd ..
}

install_driver() {
    local ver
    
    bold "Installing rtl88x2bu driver"
    
    # Install the driver package
    cd debs || die "Cannot find debs directory"
    if command -v dpkg >/dev/null; then
        bold "Installing driver package..."
        dpkg -i rtl88x2bu-dkms.deb || die "Driver package installation failed"
        
        # Show DKMS status
        bold "DKMS status:"
        dkms status
    else
        # For RPM systems, need to extract and install manually
        ar x rtl88x2bu-dkms.deb || die "Failed to extract deb package"
        tar xf data.tar.gz || die "Failed to extract tar archive"
        cd ..
        
        # Get version from extracted files
        ver=$(echo debs/usr/src/*-*)
        ver=${ver##*-}
        
        # Install the driver
        rm -rf "/usr/src/rtl88x2bu-$ver"
        mv "debs/usr/src/rtl88x2bu-$ver" /usr/src/ || die "Failed to move source files"
        
        # Build and install with dkms
        cd "/usr/src/rtl88x2bu-$ver" || die "Failed to change directory"
        dkms remove -m rtl88x2bu -v "$ver" --all 2>/dev/null
        
        bold "Building driver with DKMS..."
        dkms add -m rtl88x2bu -v "$ver" || die "DKMS add failed"
        dkms build -m rtl88x2bu -v "$ver" || die "DKMS build failed"
        dkms install -m rtl88x2bu -v "$ver" || die "DKMS install failed"
        
        # Show DKMS status
        bold "DKMS status:"
        dkms status
    fi
    
    # Unload competing driver if present
    if [ -d "/sys/module/rtw88_8822bu" ]; then
        bold "Unloading the rtw88_8822bu in-kernel driver"
        if ! modprobe -r rtw88_8822bu; then
            bold "Failed to unload the rtw88_8822bu in-kernel driver, PLEASE REBOOT"
        fi
    fi
    
    # Load our driver
    bold "Loading the driver module..."
    modprobe 88x2bu || die "Failed to load driver module"
    
    # Show loaded module info
    bold "Loaded module information:"
    lsmod | grep -E "88x2bu|rtw88" || true
}

main() {
    # Check for root access
    if [ "$(id -u)" -ne 0 ]; then
        die "This script must be run as root"
    fi

    # Ensure PATH includes sbin directories
    if ! echo "$PATH" | grep -qw sbin; then
        export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    fi

    # Check if we're in the right directory
    if [ ! -d "debs" ]; then
        die "Please run this script from the directory containing the 'debs' folder"
    fi

    install_packages
    install_driver

    bold "
=====================================================
 The driver was successfully installed!
====================================================="
}

main "$@"
EOF

    chmod +x install-offline.sh
    
    echo "
====================================================================
Offline installation package has been created in: $SAVE_DIR
To install on another machine:
1. Copy the entire '$SAVE_DIR' folder to the target machine
2. cd into the '$SAVE_DIR' directory
3. Run: sudo ./install-offline.sh
===================================================================="
}

# Run the preparation function
prepare_offline
