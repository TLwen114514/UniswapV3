// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.14;

import "./library/Tick.sol";
import "./library/Position.sol";
import "./library/TickBitmap.sol";
// import "./library/TickMath.sol";

import "./interfaces/IUniswapV3MintCallback.sol";
import "./interfaces/IUniswapV3SwapCallback.sol";
import "./interfaces/IERC20.sol";

// src/UniswapV3Pool.sol
contract UniswapV3Pool {
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.Info);
    using Position for Position.Info;

    error InsufficientInputAmount();
    error InvalidTickRange();
    error ZeroLiquidity();

    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );

    int24 internal constant MIN_TICK = -887272;
    int24 internal constant MAX_TICK = -MIN_TICK;

    // Pool tokens, immutable
    address public immutable token0;
    address public immutable token1;

    struct CallbackData {
        address token0;
        address token1;
        address payer;
    }

    constructor(
        address token0_,
        address token1_,
        uint160 sqrtPriceX96,
        int24 tick
    ) {
        token0 = token0_;
        token1 = token1_;

        slot0 = Slot0({sqrtPriceX96: sqrtPriceX96, tick: tick});
    }

    // Packing variables that are read together
    // 被存储在连续的内存位置中，并只需要一次存储操作即可完成。
    // 相比之下，如果将多个状态变量分别存储在不同的内存位置中，则每个变量都需要单独进行存储操作，从而增加了gas费用。


    // 内部数据会被紧凑型打包，如果超出会进入第二个插槽；
    // 这里打包的数据加起来255位，可以比较合理的利用存储空间，节省访问的gas开销（不用访问多个插槽）
    struct Slot0 {
        // Current sqrt(P)
        uint160 sqrtPriceX96;
        // Current tick
        int24 tick;

         // the current price
    // 当前的交易价格 √P sqrt(token1/token0) Q64.96
    // uint160 sqrtPriceX96;
    // // the current tick
    // // 当前价格对应的tick index
    // int24 tick;
    // // the most-recently updated index of the observations array
    // // 最近更新的预言机数据的索引值
    // uint16 observationIndex;
    // // the current maximum number of observations that are being stored
    // // oracle 当前能存储的最大数量（数据的个数）
    // uint16 observationCardinality;
    // // the next maximum number of observations to store, triggered in observations.write
    // // Oracle 下次将要写入数据位置的索引值
    // uint16 observationCardinalityNext;
    // // the current protocol fee as a percentage of the swap fee taken on withdrawal
    // // represented as an integer denominator (1/x)%
    // // 当前的协议费率 uint8类型 前4位代表 x 换成 y 的费率 后4位反之
    // // 协议费率的 x 为计算费率的时候的分母
    // // 即 protocolFee = fee * (1/x)%
    // // x = 0 或 4 <= x <= 10 的整数
    // uint8 feeProtocol;
    // // whether the pool is locked
    // // 防止重入攻击的互斥锁
    // bool unlocked;
    }

    Slot0 public slot0;

    // Amount of liquidity, L.
    uint128 public liquidity;

    // Ticks info
    mapping(int24 => Tick.Info) public ticks;
    // Positions info
    mapping(bytes32 => Position.Info) public positions;
    mapping(int16 => uint256) public tickBitmap;

/**
    token 所有者的地址，来识别是谁提供的流动性；
    上界和下界的 tick，来设置价格区间的边界；
    希望提供的流动性的数量
*/
    function mint(
        address owner,
        int24 lowerTick,
        int24 upperTick,
        uint128 amount,
        bytes calldata data
    ) external returns (uint256 amount0, uint256 amount1) {
        if (
            lowerTick >= upperTick ||
            lowerTick < MIN_TICK ||
            upperTick > MAX_TICK
        ) revert InvalidTickRange();

        if (amount == 0) revert ZeroLiquidity();

        bool flippedLower = ticks.update(lowerTick, amount);
        bool flippedUpper = ticks.update(upperTick, amount);
    // 此时如果为true,则表示是未初始化的,就需要更新让其初始化,后一个参数时tickSpaceing
        if (flippedLower) {
            tickBitmap.flipTick(lowerTick, 1);
        }

        if (flippedUpper) {
            tickBitmap.flipTick(upperTick, 1);
        }



        // ticks.update(lowerTick, amount);
        // ticks.update(upperTick, amount);

        Position.Info storage position = positions.get(
            owner,
            lowerTick,
            upperTick
        );
        position.update(amount);

        amount0 = 0.998976618347425280 ether; // TODO: replace with calculation
        amount1 = 5000 ether; // TODO: replace with calculation

        liquidity += uint128(amount);

        uint256 balance0Before;
        uint256 balance1Before;
        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();
        IUniswapV3MintCallback(msg.sender).uniswapV3MintCallback(
            amount0,
            amount1,
            data
        );
        if (amount0 > 0 && balance0Before + amount0 > balance0())
            revert InsufficientInputAmount();
        if (amount1 > 0 && balance1Before + amount1 > balance1())
            revert InsufficientInputAmount();

        emit Mint(
            msg.sender,
            owner,
            lowerTick,
            upperTick,
            amount,
            amount0,
            amount1
        );
    }

 
    function swap(address recipient, bytes calldata data)
        public
        returns (int256 amount0, int256 amount1)
    {
        int24 nextTick = 85184;
        uint160 nextPrice = 5604469350942327889444743441197;

        amount0 = -0.008396714242162444 ether;
        amount1 = 42 ether;

        (slot0.tick, slot0.sqrtPriceX96) = (nextTick, nextPrice);

        IERC20(token0).transfer(recipient, uint256(-amount0));

        uint256 balance1Before = balance1();
        IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(
            amount0,
            amount1,
            data
        );
        if (balance1Before + uint256(amount1) > balance1())
            revert InsufficientInputAmount();

        emit Swap(
            msg.sender,
            recipient,
            amount0,
            amount1,
            slot0.sqrtPriceX96,
            liquidity,
            slot0.tick
        );
    }

    function balance0() internal returns (uint256 balance) {
        balance = IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal returns (uint256 balance) {
        balance = IERC20(token1).balanceOf(address(this));
    }
}
