#!/bin/bash
BGreen='\033[1;32m'
Cyan='\033[0;36m'
Blue='\033[0;34m'
BIGreen='\033[1;92m'
NC='\033[0m'

#Clone rom
echo -e "${BIGreen}Cloning Rom${NC}"
repo init --depth=1 --no-repo-verify -u  https://github.com/Miku-UI/manifesto -b TDA
repo sync -c --no-clone-bundle --optimized-fetch --prune --force-sync -j$(nproc --all)
if [ $? -ne 0 ]; then
echo "First Sync failed. Aborting."
        exit 1
fi


# Device Tree
if [[ -d "device/xiaomi/vayu" ]]; then
echo -e "${BIGreen}Dt Present${NC}"
echo ""
else
echo -e "${Cyan}Dt  not present, cloning Device tree${NC}"
git clone  https://github.com/kuroringo90/device_xiaomi_vayu-baga.git  device/xiaomi/vayu
fi

echo ""

echo ""

# Kernel
if [[ -d "kernel/xiaomi/sm8150" ]]; then
echo -e "${BIGreen}Kernel Present${NC}"
echo ""
else
echo -e "${Cyan}Kernel is not present, cloning Device tree${NC}"
git clone --depth=1 -b  13.1-xsa https://github.com/kuroringo90/android_kernel_xiaomi_vayu-p.git kernel/xiaomi/vayu
fi

echo ""

# Vendor Tree
if [[ -d "vendor/xiaomi" ]]; then
echo -e "${BIGreen}Vendor present${NC}"
echo ""
else
# Vendor Tree
git clone --depth=1  https://github.com/Bagualisson/vendor_xiaomi_vayu.git vendor/xiaomi/vayu
fi

echo ""

# Kernel toolchain
echo -e "${BIGreen}Cloning Kernel Toolchain${NC}"
echo ""
git clone --depth=1 https://gitlab.com/kuroringo901/android-prebuilts-clang-host-linux-x86-clang-r487747.git prebuilts/clang/host/linux-x86/clang-latest

git clone https://github.com/PixelExperience/hardware_xiaomi.git hardware/xiaomi
rm -rf hardware/xiaomi/hidl/powershare
rm -rf hardware/xiaomi/hidl/touch

git clone https://github.com/VoidUI-Tiramisu/packages_resources_devicesettings.git packages/resources/devicesettings

rm -rf  packages/apps/Settings
git clone https://github.com/kuroringo90/platform_packages_apps_Settings-1.git packages/apps/Settings
