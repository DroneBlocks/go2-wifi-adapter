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
