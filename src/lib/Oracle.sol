// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.14;

library Oracle {
    struct Observation {
        // 记录区块的时间戳
        uint32 timestamp;
        // tick index 的时间加权累积值
        int56 tickCumulative;
        bool initialized;
    }

    function initialize(Observation[65535] storage self, uint32 time)
        internal
        returns (uint16 cardinality, uint16 cardinalityNext)
    {
        self[0] = Observation({timestamp: time, tickCumulative: 0, initialized: true});

        cardinality = 1;
        cardinalityNext = 1;
    }

    function write(
        Observation[65535] storage self,
        uint16 index,
        uint32 timestamp,
        int24 tick,
        uint16 cardinality,
        uint16 cardinalityNext
    ) internal returns (uint16 indexUpdated, uint16 cardinalityUpdated) {
        Observation memory last = self[index];
        // 同一个区块内，只会在第一笔交易中写入 Oracle 数据
        if (last.timestamp == timestamp) return (index, cardinality);
        // 检查是否需要使用新的数组空间
        if (cardinalityNext > cardinality && index == (cardinality - 1)) {
            cardinalityUpdated = cardinalityNext;
        } else {
            cardinalityUpdated = cardinality;
        }

        // 本次写入的索引，使用余数实现
        indexUpdated = (index + 1) % cardinalityUpdated;
        // 写入 Oracle 数据
        self[indexUpdated] = transform(last, timestamp, tick);
    }

    function grow(Observation[65535] storage self, uint16 current, uint16 next) internal returns (uint16) {
        if (next <= current) return current;

        for (uint16 i = current; i < next; i++) {
            self[i].timestamp = 1;
        }

        return next;
    }

    function transform(Observation memory last, uint32 timestamp, int24 tick)
        internal
        pure
        returns (Observation memory)
    {
        // 上次 Oracle 数据和本次的时间差
        uint56 delta = timestamp - last.timestamp;

        return Observation({
            timestamp: timestamp,
            // 计算 tick index 的时间加权累积值
            tickCumulative: last.tickCumulative + int56(tick) * int56(delta),
            initialized: true
        });
    }

    function lte(uint32 time, uint32 a, uint32 b) private pure returns (bool) {
        if (a <= time && b <= time) return a <= b;

        uint256 aAdjusted = a > time ? a : a + 2 ** 32;
        uint256 bAdjusted = b > time ? b : b + 2 ** 32;

        return aAdjusted <= bAdjusted;
    }

    function binarySearch(Observation[65535] storage self, uint32 time, uint32 target, uint16 index, uint16 cardinality)
        private
        view
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        uint256 l = (index + 1) % cardinality;
        uint256 r = l + cardinality - 1;
        uint256 i;
        while (true) {
            i = (l + r) / 2;

            beforeOrAt = self[i % cardinality];

            if (!beforeOrAt.initialized) {
                l = i + 1;
                continue;
            }

            atOrAfter = self[(i + 1) % cardinality];

            bool targetAtOrAfter = lte(time, beforeOrAt.timestamp, target);

            if (targetAtOrAfter && lte(time, target, atOrAfter.timestamp)) {
                break;
            }

            if (!targetAtOrAfter) r = i - 1;
            else l = i + 1;
        }
    }

    ///@notice 在已记录的 Oracle 数组中，找到时间戳离其最近的两个 Oracle 数据
    function getSurroundingObservations(
        Observation[65535] storage self,
        uint32 time,
        uint32 target,
        int24 tick,
        uint16 index,
        uint16 cardinality
    ) private view returns (Observation memory beforeOrAt, Observation memory atOrAfter) {
        // 先把 beforeOrAt 设置为当前最新数据
        beforeOrAt = self[index];

        if (lte(time, beforeOrAt.timestamp, target)) {
            if (beforeOrAt.timestamp == target) {
                // 如果时间戳相等，那么可以忽略 atOrAfter 直接返回
                return (beforeOrAt, atOrAfter);
            } else {
                // 当前区块中发生代币对的交易之前请求此函数时可能会发生这种情况
                // 需要将当前还未持久化的数据，封装成一个 Oracle 数据返回
                return (beforeOrAt, transform(beforeOrAt, target, tick));
            }
        }

        // 将 beforeOrAt 调整至 Oracle 数组中最老的数据
        // 即为当前 index 的下一个数据，或者 index 为 0 的数据
        beforeOrAt = self[(index + 1) % cardinality];
        if (!beforeOrAt.initialized) beforeOrAt = self[0];

        require(lte(time, beforeOrAt.timestamp, target), "OLD");

        // 然后通过二分查找的方式找到离目标时间点最近的前后两个 Oracle 数据
        return binarySearch(self, time, target, index, cardinality);
    }

    function observeSingle(
        Observation[65535] storage self,
        uint32 time,
        uint32 secondsAgo,
        int24 tick,
        uint16 index,
        uint16 cardinality
    ) internal view returns (int56 tickCumulative) {
        // 当secondsAgo传0 返回最新的一个Oracle数据
        if (secondsAgo == 0) {
            Observation memory last = self[index];
            // 区块时间戳 不等于 Oracle最新的时间戳，更新last
            if (last.timestamp != time) last = transform(last, time, tick);
            return last.tickCumulative;
        }

        // 当secondsAgo不为0
        // 计算时间区间的另一个点
        uint32 target = time - secondsAgo;

        // 计算出请求时间戳最近的两个 Oracle 数据
        (Observation memory beforeOrAt, Observation memory atOrAfter) =
            getSurroundingObservations(self, time, target, tick, index, cardinality);

        if (target == beforeOrAt.timestamp) {
            // 如果请求时间和返回的左侧时间戳吻合，那么可以直接使用
            return beforeOrAt.tickCumulative;
        } else if (target == atOrAfter.timestamp) {
            // 如果请求时间和返回的右侧时间戳吻合，那么可以直接使用
            return atOrAfter.tickCumulative;
        } else {
            uint56 observationTimeDelta = atOrAfter.timestamp - beforeOrAt.timestamp;
            uint56 targetDelta = target - beforeOrAt.timestamp;
            return beforeOrAt.tickCumulative
                + ((atOrAfter.tickCumulative - beforeOrAt.tickCumulative) / int56(observationTimeDelta))
                    * int56(targetDelta);
        }
    }

    function observe(
        Observation[65535] storage self,
        uint32 time,
        uint32[] memory secondsAgos,
        int24 tick,
        uint16 index,
        uint16 cardinality
    ) internal view returns (int56[] memory tickCumulatives) {
        tickCumulatives = new int56[](secondsAgos.length);

        for (uint256 i = 0; i < secondsAgos.length; i++) {
            tickCumulatives[i] = observeSingle(self, time, secondsAgos[i], tick, index, cardinality);
        }
    }
}
