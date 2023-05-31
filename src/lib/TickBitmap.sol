// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.5.0;

import "./BitMath.sol";

library TickBitmap {
    /// @notice 翻转tick的初始化状态， 未初始化 -> 初始化，反之亦然
    function position(int24 tick) private pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8);
        bitPos = uint8(uint24(tick % 256));
    }

    /// @notice 翻转tick的初始化状态， 未初始化 -> 初始化，反之亦然
    function flipTick(mapping(int16 => uint256) storage self, int24 tick, int24 tickSpacing) internal {
        require(tick % tickSpacing == 0); // ensure that the tick is spaced
        (int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
        uint256 mask = 1 << bitPos;
        self[wordPos] ^= mask;
    }

    /// @notice 传入starting tick(可能未初始化),
    /// 在其所在的word内寻找最近离starting tick最近的已初始化的tick，
    /// 若没有已初始化的tick，返回word的边界。
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        /// true 为寻找价格较小的tick包括 starting tick 本身
        /// false 为寻找较大价格的tick
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        // 计算传入position函数的入参
        int24 compressed = tick / tickSpacing;
        // 若tick < 0 , 需要 -1
        // 若tick >= 0, 因为正数轴上第一个wordPos是0，所以不需要+1
        if (tick < 0 && tick % tickSpacing != 0) compressed--; // round towards negative infinity

        // 搜索价格较小的next(next tick <= starting tick)
        if (lte) {
            // 获取wordPos bitPos
            (int16 wordPos, uint8 bitPos) = position(compressed);
            // mask 在二进制下是 1...1 (bitPos+1 个 1)
            uint256 mask = (1 << bitPos) - 1 + (1 << bitPos);
            uint256 masked = self[wordPos] & mask;

            // 在word内，小于等于 starting tick 的价格是否有已初始化的tick
            initialized = masked != 0;

            // 上溢或下溢都是有可能的，但这里限制了 tickSpacing 和 tick 防止这种情况发生
            // 当有初始化tick时，查找小于 starting tick 价格最近的已初始化tick
            // 即 查找word内，starting tick右侧距离最近值为1的位
            // 没有初始化时，直接返回word的右边界（tickindex最小）
            next = initialized
                ? (compressed - int24(bitPos - BitMath.mostSignificantBit(masked))) * tickSpacing
                : (compressed - int24(bitPos)) * tickSpacing;
        } else {
            // 搜索价格较大的next(next tick > starting tick) 不包括 starting tick
            // 直接从 compressed + 1 开始搜索，因为这里搜索的目标范围不包括 starting tick 本身
            (int16 wordPos, uint8 bitPos) = position(compressed + 1);
            // 获得掩码 111...110...0 形式，共256位，bitPos 个0，前面全是1
            uint256 mask = ~((1 << bitPos) - 1);
            uint256 masked = self[wordPos] & mask;

            // 在word内，大于 starting tick 的价格是否有已初始化的tick
            initialized = masked != 0;

            // 当有初始化tick时，查找大于 starting tick 价格最近的已初始化tick
            // 即 查找word内，starting tick左侧距离最近值为1的位
            // 没有初始化时，直接返回word的右边界（tickindex最小）
            next = initialized
                ? (compressed + 1 + int24(BitMath.leastSignificantBit(masked) - bitPos)) * tickSpacing
                : (compressed + 1 + int24(type(uint8).max - bitPos)) * tickSpacing;
        }
    }

