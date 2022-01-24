// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import { IERC20 } from "./external/openzeppelin/token/ERC20/IERC20.sol";
import { ERC20 } from "./external/openzeppelin/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "./external/openzeppelin/security/ReentrancyGuard.sol";
import { ISwapRouter } from "./external/uniswap/v3-periphery/ISwapRouter.sol";
import { IUniswapV3Factory } from "./external/uniswap/v3-core/IUniswapV3Factory.sol";
import { IUniswapV3Pool } from "./external/uniswap/v3-core/IUniswapV3Pool.sol";
import { AggregatorInterface } from "./external/chainlink/AggregatorInterface.sol";

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

contract MultiTokenCellar is ERC20, ReentrancyGuard {
    struct GeneralRebalanceInput {
        uint184 amount;
        int24 direction; // 0: Eth -> token, 1:token -> Eth
        int24 currentTick;
        uint24 feeLevel;
    }

    struct SwapPoolInfo {
        uint24 feeLevel;
        int24 currentTick;
    }

    uint256 public constant TOKENCOUNT = 4;
    address public constant SWAPROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant SWAPFACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address public constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address public constant SOL = 0xD31a59c85aE9D8edEFeC411D448f90841571b89c;
    address public constant ETH_USD_PRICE_FEED = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public constant BTC_ETH_PRICE_FEED = 0xdeb288F737066589598e9214E782fa5A8eD689e8;
    address public constant UNI_ETH_PRICE_FEED = 0xD6aA3D25116d8dA79Ea0246c4826EB951872e02e;
    address public constant LINK_ETH_PRICE_FEED = 0xDC530D9457755926550b59e8ECcdaE7624181557;
    address public constant SOL_USD_PRICE_FEED = 0x4ffC43a60e009B551865A93d232E33Fce9f01507;

    constructor(string memory name, string memory symbol)
        ERC20(name, symbol)
    {
    }

    function rebalance(GeneralRebalanceInput[] calldata rebalanceInput, uint256) external {
        address[TOKENCOUNT] memory assets = [WBTC, UNI, LINK, SOL];
        for (uint256 i = 0; i < TOKENCOUNT; i++) {
            if (rebalanceInput[i].amount > 0 && rebalanceInput[i].direction == 1) {
                address asset = assets[i];
                IUniswapV3Pool pool = IUniswapV3Pool(IUniswapV3Factory(SWAPFACTORY).getPool(WETH, asset, rebalanceInput[i].feeLevel));
                (, int24 tick, , , , , ) = pool.slot0();
                int24 tickSpace = pool.tickSpacing();
                require(rebalanceInput[i].currentTick + tickSpace >= tick && rebalanceInput[i].currentTick - tickSpace <= tick, "High Slippage");
                IERC20(asset).approve(SWAPROUTER, 0);
                IERC20(asset).approve(SWAPROUTER, rebalanceInput[i].amount);
                uint256 amountOut = ISwapRouter(SWAPROUTER).exactInputSingle(
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: asset,
                        tokenOut: WETH,
                        fee: rebalanceInput[i].feeLevel,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: rebalanceInput[i].amount,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    })
                );
                IWETH(WETH).withdraw(amountOut);
            }
        }
        uint256 ethBalance = address(this).balance;
        IWETH(WETH).deposit{value: ethBalance}();
        IERC20(WETH).approve(SWAPROUTER, ethBalance);
        for (uint256 i = 0; i < TOKENCOUNT; i++) {
            if (rebalanceInput[i].amount > 0 && rebalanceInput[i].direction == 0) {
                address asset = assets[i];
                IUniswapV3Pool pool = IUniswapV3Pool(IUniswapV3Factory(SWAPFACTORY).getPool(WETH, asset, rebalanceInput[i].feeLevel));
                (, int24 tick, , , , , ) = pool.slot0();
                int24 tickSpace = pool.tickSpacing();
                require(rebalanceInput[i].currentTick + tickSpace >= tick && rebalanceInput[i].currentTick - tickSpace <= tick, "High Slippage");
                ISwapRouter(SWAPROUTER).exactOutputSingle(
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
            }
        }
        IWETH(WETH).withdraw(IWETH(WETH).balanceOf(address(this)));
    }

    function addCapital() external payable {
        require(msg.value > 0, "Can not add 0 Eth");
        uint256 newCap = msg.value;
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            _mint(msg.sender, newCap);
        } else {
            uint256 cap = (address(this).balance - msg.value);
            cap += IERC20(WBTC).balanceOf(address(this)) * uint256(AggregatorInterface(BTC_ETH_PRICE_FEED).latestAnswer()) / 10 ** 18;
            cap += IERC20(UNI).balanceOf(address(this)) * uint256(AggregatorInterface(UNI_ETH_PRICE_FEED).latestAnswer()) / 10 ** 18;
            cap += IERC20(LINK).balanceOf(address(this)) * uint256(AggregatorInterface(LINK_ETH_PRICE_FEED).latestAnswer()) / 10 ** 18;
            cap += IERC20(SOL).balanceOf(address(this)) * uint256(AggregatorInterface(SOL_USD_PRICE_FEED).latestAnswer()) / uint256(AggregatorInterface(ETH_USD_PRICE_FEED).latestAnswer());
            _mint(msg.sender, _totalSupply * newCap / cap);
        }
    }

    function removeCapital(uint256 share, SwapPoolInfo[TOKENCOUNT] calldata swapPoolInfo) external nonReentrant {
        address[TOKENCOUNT] memory assets = [WBTC, UNI, LINK, SOL];
        uint256 _totalSupply = totalSupply();
        IWETH(WETH).withdraw(IERC20(WETH).balanceOf(address(this)));
        uint256 remainBalance = address(this).balance * (_totalSupply - share) / _totalSupply;
        for (uint256 i = 0; i < TOKENCOUNT; i++) {
            address asset = assets[i];
            IUniswapV3Pool pool = IUniswapV3Pool(IUniswapV3Factory(SWAPFACTORY).getPool(WETH, asset, swapPoolInfo[i].feeLevel));
            (, int24 tick, , , , , ) = pool.slot0();
            int24 tickSpace = pool.tickSpacing();
            require(swapPoolInfo[i].currentTick + tickSpace >= tick && swapPoolInfo[i].currentTick - tickSpace <= tick, "High Slippage");
            uint256 amount = IERC20(asset).balanceOf(address(this)) * share / _totalSupply;
            if (amount > 0) {
                IERC20(asset).approve(SWAPROUTER, 0);
                IERC20(asset).approve(SWAPROUTER, amount);
                ISwapRouter(SWAPROUTER).exactInputSingle(
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: asset,
                        tokenOut: WETH,
                        fee: swapPoolInfo[i].feeLevel,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: amount,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    })
                );
            }
        }
        IWETH(WETH).withdraw(IERC20(WETH).balanceOf(address(this)));
        payable(msg.sender).transfer(address(this).balance - remainBalance);
        _burn(msg.sender, share);
    }

    receive() external payable {

    }
}
