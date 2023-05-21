// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./LiquidityMath.sol";
import "./Math.sol";

library Tick {
    struct Info {
        bool initialized;
        // 该tick上 所有position的流动性累加
        uint128 liquidityGross;
        // 该tick上 所有position的流动性净值
        int128 liquidityNet;
        // 每单位流动性的 手续费数量 outside （相对于当前交易价格的另一边）
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
    }
    /**
     * @notice 更新tick的状态，返回激活状态是否发生改变
     */

    function update(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        int24 currentTick,
        int128 liquidityDelta,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128,
        bool upper
    ) internal returns (bool flipped) {
        Tick.Info storage tickInfo = self[tick];

        uint128 liquidityBefore = tickInfo.liquidityGross;
        uint128 liquidityAfter = LiquidityMath.addLiquidity(liquidityBefore, liquidityDelta);

        // 返回当前tick的激活状态是否发生了改变
        // 激活 -> 未激活 | 未激活 -> 激活
        // 根据流动性总量是否为0来判断激活状态 为0未激活
        flipped = (liquidityAfter == 0) != (liquidityBefore == 0);
        // 如果tick之前未激活 需要对tick进行初始化并激活
        if (liquidityBefore == 0) {
            // 这里规定当价格在tick左侧
            // feeOutside = Pool的总手续费
            // feeOutside为外侧手续费， 外侧手续费 + 内侧 = 总手续费
            if (tick <= currentTick) {
                tickInfo.feeGrowthOutside0X128 = feeGrowthGlobal0X128;
                tickInfo.feeGrowthOutside1X128 = feeGrowthGlobal1X128;
            }
            tickInfo.initialized = true;
        }
        // 更新tick的总流动性
        tickInfo.liquidityGross = liquidityAfter;
        // 更新tick的流动性净值 即 当价格穿过该tick时 用于计算的流动性数量
        // 当此tick作为价格上限更新时 流动性净值需要减
        // 当此tick作为价格下限更新时 流动性净值需要加
        tickInfo.liquidityNet = upper
            ? int128(int256(tickInfo.liquidityNet) - liquidityDelta)
            : int128(int256(tickInfo.liquidityNet) + liquidityDelta);
    }

    ///@notice 当价格穿过tick时，需要对tick状态做出改变
    function cross(
        mapping(int24 => Tick.Info) storage self,
        int24 tick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal returns (int128 liquidityDelta) {
        Tick.Info storage info = self[tick];
        //新的fo = fg-fo
        info.feeGrowthOutside0X128 = feeGrowthGlobal0X128 - info.feeGrowthOutside0X128;
        info.feeGrowthOutside1X128 = feeGrowthGlobal1X128 - info.feeGrowthOutside1X128;
        liquidityDelta = info.liquidityNet;
    }

    /// @notice 检索手续费数据 返回feeInside
    function getFeeGrowthInside(
        mapping(int24 => Tick.Info) storage self,
        int24 lowerTick_,
        int24 upperTick_,
        int24 currentTick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal view returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) {
        Tick.Info storage lowerTick = self[lowerTick_];
        Tick.Info storage upperTick = self[upperTick_];

        uint256 feeGrowthBelow0X128;
        uint256 feeGrowthBelow1X128;
        if (currentTick >= lowerTick_) {
            feeGrowthBelow0X128 = lowerTick.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = lowerTick.feeGrowthOutside1X128;
        } else {
            feeGrowthBelow0X128 = feeGrowthGlobal0X128 - lowerTick.feeGrowthOutside0X128;
            feeGrowthBelow1X128 = feeGrowthGlobal1X128 - lowerTick.feeGrowthOutside1X128;
        }

        uint256 feeGrowthAbove0X128;
        uint256 feeGrowthAbove1X128;
        if (currentTick < upperTick_) {
            feeGrowthAbove0X128 = upperTick.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = upperTick.feeGrowthOutside1X128;
        } else {
            feeGrowthAbove0X128 = feeGrowthGlobal0X128 - upperTick.feeGrowthOutside0X128;
            feeGrowthAbove1X128 = feeGrowthGlobal1X128 - upperTick.feeGrowthOutside1X128;
        }

        feeGrowthInside0X128 = feeGrowthGlobal0X128 - feeGrowthBelow0X128 - feeGrowthAbove0X128;
        feeGrowthInside1X128 = feeGrowthGlobal1X128 - feeGrowthBelow1X128 - feeGrowthAbove1X128;
    }
}
