// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ISwapRouter } from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import { IUniswapV3Factory } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

interface IWETH is IERC20{
    /**
     * @dev wrap ETH into WETH
     */
    function deposit() external payable;

    /**
     * @dev unwrap WETH into ETH
     */
    function withdraw(uint256) external;
}

contract MultiTokenCellar is ERC20 {
    struct GeneralRebalanceInput {
        uint184 amount;
        int24 direction; // 0: Eth -> token, 1:token -> Eth
        int24 currentTick;
        uint24 feeLevel;
    }

    uint256 public constant TOKENCOUNT = 4;
    address[TOKENCOUNT] public assets;
    ISwapRouter public constant SWAPROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapV3Factory public constant SWAPFACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    constructor(string memory name, string memory symbol, uint256 tokenCount, address[] memory tokens)
        ERC20(name, symbol)
    {
        require(tokens.length == tokenCount);
        for (uint256 i = 0; i < 5; i++) {
            assets[i] = tokens[i];
        }
    }

    function rebalance(GeneralRebalanceInput[] calldata rebalanceInput, uint256) external {
        for (uint256 i = 0; i < TOKENCOUNT - 1; i++) {
            if (rebalanceInput[i].direction == 0) {
                address asset = assets[i];
                uint256 ethBalance = address(this).balance;
                IUniswapV3Pool pool = IUniswapV3Pool(SWAPFACTORY.getPool(WETH, asset, rebalanceInput[i].feeLevel));
                (, int24 tick, , , , , ) = pool.slot0();
                int24 tickSpace = pool.tickSpacing();
                require(rebalanceInput[i].currentTick + tickSpace >= tick && rebalanceInput[i].currentTick - tickSpace <= tick, "High Slippage");
                ISwapRouter(SWAPROUTER).exactOutputSingle{value: ethBalance}(
                    ISwapRouter.ExactOutputSingleParams({
                        tokenIn: WETH,
                        tokenOut: asset,
                        fee: rebalanceInput[i].feeLevel,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountOut: rebalanceInput[i].amount,
                        amountInMaximum: ethBalance,
                        sqrtPriceLimitX96: 0
                    })
                );
            } else if (rebalanceInput[i].direction == 1) {
                address asset = assets[i];
                IUniswapV3Pool pool = IUniswapV3Pool(SWAPFACTORY.getPool(WETH, asset, rebalanceInput[i].feeLevel));
                (, int24 tick, , , , , ) = pool.slot0();
                int24 tickSpace = pool.tickSpacing();
                require(rebalanceInput[i].currentTick + tickSpace >= tick && rebalanceInput[i].currentTick - tickSpace <= tick, "High Slippage");
                ISwapRouter(SWAPROUTER).exactInputSingle(
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: WETH,
                        tokenOut: asset,
                        fee: rebalanceInput[i].feeLevel,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: rebalanceInput[i].amount,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    })
                );
            }
        }
    }

    receive() external payable {

    }
}
