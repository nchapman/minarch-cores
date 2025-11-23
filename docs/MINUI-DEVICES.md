# MinUI Device Compatibility

Which architecture to use for MinUI devices.

## ARM32 Devices

Use **linux-arm32.zip**

| Device | SoC | Notes |
|--------|-----|-------|
| Miyoo Mini | Allwinner R16 (Cortex-A7) | Primary target |
| Miyoo Mini Plus | Allwinner R16 (Cortex-A7) | Primary target |
| Miyoo A30 | Allwinner A33 (Cortex-A7) | |
| Trimui Smart | Allwinner F1C100s (ARM926) | |
| Anbernic RG35XX | Allwinner H700 (Cortex-A53, 32-bit mode) | Can also use arm64 |
| Anbernic RG35XX Plus | Allwinner H700 (Cortex-A53, 32-bit mode) | Can also use arm64 |

## ARM64 Devices

Use **linux-arm64.zip**

### H700/A133 Devices (Cortex-A53)

| Device | SoC |
|--------|-----|
| Anbernic RG28xx | Allwinner H700 |
| Anbernic RG34xx | Allwinner H700 |
| Anbernic RG35xx Plus | Allwinner H700 |
| Anbernic RG40xxH/V | Allwinner H700 |
| Anbernic CubeXX | Allwinner H700 |
| Trimui Brick | Allwinner A133 Plus |
| Trimui Smart Pro | Allwinner A133 Plus |

### RK3566 Devices (Cortex-A55, compatible with A53 baseline)

| Device | SoC |
|--------|-----|
| Miyoo Flip | Rockchip RK3566 |
| Powkiddy RGB30 | Rockchip RK3566 |
| Anbernic RG353 series | Rockchip RK3566 |

**Note:** arm64 uses Cortex-A53 baseline, fully compatible with all ARM64 devices.

## Summary

- **arm32:** ~6 ARM32 devices (Miyoo Mini family, RG35XX, Trimui)
- **arm64:** 15+ ARM64 devices (H700, A133, RK3566 SoCs)
- **Total:** 20+ MinUI-compatible devices
