// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

// 价格点
library Tick {
    struct Info {
        bool initialized;
        uint128 liquidity;


            // the total position liquidity that references this tick
    // 该tick上 所有position的流动性累加
    // uint128 liquidityGross;
    // // amount of net liquidity added (subtracted) when tick is crossed from left to right (right to left),
    // // 该tick上 所有position的流动性净值
    // int128 liquidityNet;
    // // fee growth per unit of liquidity on the _other_ side of this tick (relative to the current tick)
    // // 每单位流动性的 手续费数量 outside （相对于当前交易价格的另一边）
    // // only has relative meaning, not absolute — the value depends on when the tick is initialized
    // // 这只是一个相对的概念，并不是绝对的数值（手续费的计算工具，而并不是实际的手续费）
    // // 只有当tick已经初始化后，才会被使用
    // uint256 feeGrowthOutside0X128;
    // uint256 feeGrowthOutside1X128;
    // // the cumulative tick value on the other side of the tick
    // // tick 外侧（outside）的 价格 × 时间 累加值
    // // 用于 Oracle 的相关计算
    // int56 tickCumulativeOutside;
    // // the seconds per unit of liquidity on the _other_ side of this tick (relative to the current tick)
    // // 每流动性单位的 tick激活时间 (t/L 主要用于计算流动性挖矿的收益) （outside)
    // // only has relative meaning, not absolute — the value depends on when the tick is initialized
    // // 这只是一个相对的概念，并不是绝对的数值 -- 只有当tick已经初始化后，才会被使用
    // uint160 secondsPerLiquidityOutsideX128;
    // // the seconds spent on the other side of the tick (relative to the current tick)
    // // tick激活时间 （outside）
    // // only has relative meaning, not absolute — the value depends on when the tick is initialized
    // // 这只是一个相对的概念，并不是绝对的数值 -- 只有当tick已经初始化后，才会被使用
    // uint32 secondsOutside;
    // // true iff the tick is initialized, i.e. the value is exactly equivalent to the expression liquidityGross != 0
    // // tick是否初始化 即 该值完全等同于表达式 liquidityGross != 0 
    // // these 8 bits are set to prevent fresh sstores when crossing newly initialized ticks
    // // 这个参数的目的是为了防止tick未初始化时，发生更新和存储状态的操作
    // bool initialized;
    }

    function update(
        mapping(int24 => Info) storage self,
        int24 tick,
        uint128 liquidityDelta
    ) internal returns (bool flipped){
        Tick.Info storage tickInfo = self[tick];
        uint128 liquidityBefore = tickInfo.liquidity;
        uint128 liquidityAfter = liquidityBefore + liquidityDelta;
    // 流动性被添加到一个空的 tick 或整个 tick 的流动性被耗尽时为 true。
        flipped = (liquidityAfter == 0) != (liquidityBefore == 0);

        if (liquidityBefore == 0) {
            tickInfo.initialized = true;
        }

        tickInfo.liquidity = liquidityAfter;
    }
}