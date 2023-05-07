// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./Math.sol";

library SwapMath {
    /**
     * 根据传入的参数判断交换的方向，具体的判断方式是比较当前池子价格和目标价格。如果当前池子价格高于目标价格，则表示用户想要买入；反之则表示用户想要卖出。
     * 计算需要输入或输出的金额。对于精确匹配剩余的输入或输出金额的情况，直接使用已知的剩余金额即可；对于不精确匹配的情况，还需要根据当前池子价格和流动性等因素进行一定的计算得到需要输入或输出的金额。
     * 根据剩余的输入或输出金额以及手续费百分比来计算最终的池子价格。如果剩余的输入或输出金额大于等于需要输入或输出的金额加上手续费，那么价格就是目标价格；否则，需要根据剩余的输入或输出金额来调整池子价格。
     * 根据最终的池子价格、交换方向以及其他参数计算出实际的输入金额、输出金额和手续费金额。需要注意的是，在计算输出金额时可能会存在限制，即不能超过剩余的输出金额。
     */
    function computeSwapStep(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        uint256 amountRemaining
    ) internal pure returns (uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut) {
        bool zeroForOne = sqrtPriceCurrentX96 >= sqrtPriceTargetX96;

        sqrtPriceNextX96 = Math.getNextSqrtPriceFromInput(sqrtPriceCurrentX96, liquidity, amountRemaining, zeroForOne);

        // 考虑当前tick能否满足
        amountIn = zeroForOne
            ? Math.calcAmount0Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity)
            : Math.calcAmount1Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity);

        if (amountRemaining >= amountIn) {
            sqrtPriceNextX96 = sqrtPriceTargetX96;
        } else {
            sqrtPriceNextX96 =
                Math.getNextSqrtPriceFromInput(sqrtPriceCurrentX96, liquidity, amountRemaining, zeroForOne);
        }
        amountIn = Math.calcAmount0Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity);
        amountOut = Math.calcAmount1Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity);
        if (!zeroForOne) {
            (amountIn, amountOut) = (amountOut, amountIn);
        }
    }
}
