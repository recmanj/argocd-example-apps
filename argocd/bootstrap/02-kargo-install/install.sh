#!/bin/bash
set -e

echo "=== Kargo Multi-Cluster Installation ==="
echo ""
echo "Kargo uses a distributed architecture with:"
echo "  - Control Plane (API + default controller) in PROD cluster"
echo "  - Distributed Controllers in DEV and STAGING clusters"
echo ""
echo "What would you like to install?"
echo ""
echo "1) Control Plane (install in PROD cluster)"
echo "2) Dev Controller (install in DEV cluster)"
echo "3) Staging Controller (install in STAGING cluster)"
echo "4) Setup kubeconfig secrets"
echo "5) Exit"
echo ""
read -p "Select option (1-5): " -n 1 -r
echo ""
echo ""

case $REPLY in
    1)
        echo "Installing Kargo Control Plane..."
        ./install-controlplane.sh
        ;;
    2)
        echo "Installing Dev Controller..."
        cd controller-dev && ./install.sh
        ;;
    3)
        echo "Installing Staging Controller..."
        cd controller-staging && ./install.sh
        ;;
    4)
        echo "Setting up kubeconfig secrets..."
        echo "Please run the following:"
        echo "  cd kubeconfig-setup"
        echo "  ./create-kubeconfig.sh        # Run in PROD cluster"
        echo "  ./deploy-secret.sh dev        # Run in DEV cluster"
        echo "  ./deploy-secret.sh staging    # Run in STAGING cluster"
        ;;
    5)
        echo "Exiting."
        exit 0
        ;;
    *)
        echo "Invalid option. Exiting."
        exit 1
        ;;
esac
