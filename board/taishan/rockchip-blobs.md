# Rockchip loader binaries for RK3566 (Taishan Pi)
#
# Reuses the exact same blobs as the upstream Home Assistant Green board
# (RK3566, buildroot-external/configs/green_defconfig):
#   ATF: bin/rk35/rk3568_bl31_v1.43.elf
#   TPL: bin/rk35/rk3566_ddr_1056MHz_v1.18.bin
#
# The TPL blob is the DDR training/initializer. rk3566_ddr_1056MHz_v1.18.bin
# supports the LPDDR4 variants of the Taishan Pi (1/2/4/8 GB). If a board
# fails to train DDR, try the 920 MHz variant instead:
#   bin/rk35/rk3566_ddr_920MHz_v1.18.bin
#
# The full list of available blobs can be inspected with:
#   curl -s "https://api.github.com/repos/rockchip-linux/rkbin/contents/bin/rk35?ref=<version>" \
#     | grep rk3566_ddr
