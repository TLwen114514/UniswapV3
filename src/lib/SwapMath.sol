// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./Math.sol";

library SwapMath {
    function computeSwapStep(
        uint160 sqrtPriceCurrentX96,
        uint160 sqrtPriceTargetX96,
        uint128 liquidity,
        uint256 amountRemaining,
        uint24 fee
    ) internal pure returns (uint160 sqrtPriceNextX96, uint256 amountIn, uint256 amountOut, uint256 feeAmount) {
        bool zeroForOne = sqrtPriceCurrentX96 >= sqrtPriceTargetX96;
        uint256 amountRemainingLessFee = PRBMath.mulDiv(amountRemaining, 1e6 - fee, 1e6);
        // 通过deltaPrice（当前价格到目标价格的差）和流动性L计算deltaX
        amountIn = zeroForOne
            ? Math.calcAmount0Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, true)
            : Math.calcAmount1Delta(sqrtPriceCurrentX96, sqrtPriceTargetX96, liquidity, true);
        // 如果刨除手续费之后的输入 >= 计算得出能够交换的数量 (输入仍未被耗尽)
        // 下个价格点即为目标价格
        if (amountRemainingLessFee >= amountIn) {
            sqrtPriceNextX96 = sqrtPriceTargetX96;
        } else {
            // 如果输出被耗尽，需要重新计算交易停止的价格点
            sqrtPriceNextX96 =
                Math.getNextSqrtPriceFromInput(sqrtPriceCurrentX96, liquidity, amountRemainingLessFee, zeroForOne);
        }

        // max 交易后的价格是否达到了下一个tick对应的价格
        // 即判断交易价格是否越过了tickNext
        bool max = sqrtPriceNextX96 == sqrtPriceTargetX96;

        if (zeroForOne) {
            amountIn = max ? amountIn : Math.calcAmount0Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, true);
            amountOut = Math.calcAmount1Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, false);
        } else {
            amountIn = max ? amountIn : Math.calcAmount1Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, true);
            amountOut = Math.calcAmount0Delta(sqrtPriceCurrentX96, sqrtPriceNextX96, liquidity, false);
        }

        // 当处于 exactOutinput 调用时，需要将输出反号（入参的amountRemaining是负数）
        if (!max) {
            // 当该步交易没有越过下一个tick时，将剩余的输入token作为手续费
            feeAmount = amountRemaining - amountIn;
        } else {
            // 当该步交易越过下一个tick时，使用费率计算手续费
            // 注意这里分母是 1e6 - feePips 不是 1e6
            // 因为此时amountIn是由amountRemainingLessFee计算而来，而amountRemainingLessFee已经在最开始刨除了手续费
            feeAmount = Math.mulDivRoundingUp(amountIn, fee, 1e6 - fee);
        }
    }
}
