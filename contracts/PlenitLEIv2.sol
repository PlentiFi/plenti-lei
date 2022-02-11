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

contract BlockLock {
    error Locked();
    uint256 private constant BLOCK_LOCK_COUNT = 1;
    mapping(address => uint256) public lastLockedBlock;
    modifier notLocked(address lockedAddress) {
        if (lastLockedBlock[lockedAddress] > block.number) {
            revert Locked();
        }
        lastLockedBlock[lockedAddress] = block.number + BLOCK_LOCK_COUNT;
        _;
    }
    modifier lock(address lockedAddress) {
        lastLockedBlock[lockedAddress] = block.number + BLOCK_LOCK_COUNT;
        _;
    }
}

contract PlentiLEIv2 is ERC20, ReentrancyGuard, BlockLock {
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

    mapping(address => bool) public adjusters;
    address public admin;
    uint24[TOKENCOUNT] public feeLevels = [500, 3000, 3000, 3000];

    error NonPermission();
    error ZeroEthAdded();
    error HighSlippage();

    constructor(string memory name, string memory symbol)
        ERC20(name, symbol)
    {
        admin = msg.sender;
        adjusters[msg.sender] = true;
    }

    function transferOwnership(address newAdmin) external {
        if (msg.sender != admin) {
            revert NonPermission();
        }
        admin = newAdmin;
    }

    function setAdjuster(address adjuster, bool value) external {
        if (msg.sender != admin) {
            revert NonPermission();
        }
        adjusters[adjuster] = value;
    }

    function setFeeLevels(uint24[TOKENCOUNT] calldata _feeLevels) external {
        if (adjusters[msg.sender] == false) {
            revert NonPermission();
        }
        feeLevels = _feeLevels;
    }

    function rebalance(GeneralRebalanceInput[] calldata rebalanceInput, uint256) external notLocked(msg.sender) {
        if (adjusters[msg.sender] == false) {
            revert NonPermission();
        }
        address[TOKENCOUNT] memory assets = [WBTC, UNI, LINK, SOL];

        for (uint256 i = 0; i < TOKENCOUNT; i++) {
            if (rebalanceInput[i].amount > 0 && rebalanceInput[i].direction == 1) {
                address asset = assets[i];
                IUniswapV3Pool pool = IUniswapV3Pool(IUniswapV3Factory(SWAPFACTORY).getPool(WETH, asset, rebalanceInput[i].feeLevel));
                (, int24 tick, , , , , ) = pool.slot0();
                int24 tickSpace = pool.tickSpacing();
                if (rebalanceInput[i].currentTick + tickSpace < tick || rebalanceInput[i].currentTick - tickSpace > tick) {
                    revert HighSlippage();
                }
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
        IWETH(WETH).approve(SWAPROUTER, ethBalance);
        uint24[TOKENCOUNT] memory _feeLevels;
        for (uint256 i = 0; i < TOKENCOUNT; i++) {
            if (rebalanceInput[i].amount > 0 && rebalanceInput[i].direction == 0) {
                address asset = assets[i];
                IUniswapV3Pool pool = IUniswapV3Pool(IUniswapV3Factory(SWAPFACTORY).getPool(WETH, asset, rebalanceInput[i].feeLevel));
                (, int24 tick, , , , , ) = pool.slot0();
                int24 tickSpace = pool.tickSpacing();
                if (rebalanceInput[i].currentTick + tickSpace < tick || rebalanceInput[i].currentTick - tickSpace > tick) {
                    revert HighSlippage();
                }
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
            _feeLevels[i] = rebalanceInput[i].feeLevel;
        }
        feeLevels = _feeLevels;
        IWETH(WETH).withdraw(IWETH(WETH).balanceOf(address(this)));
    }

    function addCapital(int24[TOKENCOUNT] calldata currentTicks) external payable notLocked(msg.sender) {
        if (msg.value == 0) {
            revert ZeroEthAdded();
        }
        uint256 _totalSupply = totalSupply();
        if (_totalSupply == 0) {
            _mint(msg.sender, msg.value);
        } else {
            uint256[TOKENCOUNT + 1] memory caps;
            caps[0] = (address(this).balance - msg.value);
            caps[1] = IERC20(WBTC).balanceOf(address(this)) * uint256(AggregatorInterface(BTC_ETH_PRICE_FEED).latestAnswer()) / 10 ** 18;
            caps[2] = IERC20(UNI).balanceOf(address(this)) * uint256(AggregatorInterface(UNI_ETH_PRICE_FEED).latestAnswer()) / 10 ** 18;
            caps[3] = IERC20(LINK).balanceOf(address(this)) * uint256(AggregatorInterface(LINK_ETH_PRICE_FEED).latestAnswer()) / 10 ** 18;
            caps[4] = IERC20(SOL).balanceOf(address(this)) * uint256(AggregatorInterface(SOL_USD_PRICE_FEED).latestAnswer()) / uint256(AggregatorInterface(ETH_USD_PRICE_FEED).latestAnswer());
            uint256 totalCap = caps[0] + caps[1] + caps[2] + caps[3] + caps[4];
            caps[1] = caps[1] * msg.value / totalCap;
            caps[2] = caps[2] * msg.value / totalCap;
            caps[3] = caps[3] * msg.value / totalCap;
            caps[4] = caps[4] * msg.value / totalCap;
            uint256 swapCap = caps[1] + caps[2] + caps[3] + caps[4];
            if (swapCap > 0) {
                address[TOKENCOUNT] memory assets = [WBTC, UNI, LINK, SOL];
                uint24[TOKENCOUNT] memory _feeLevels = feeLevels;
                IWETH(WETH).deposit{value: swapCap}();
                IWETH(WETH).approve(SWAPROUTER, swapCap);
                for (uint256 i = 1; i <= TOKENCOUNT; i++) {
                    if (caps[i] > 0) {
                        address asset = assets[i - 1];
                        uint24 feeLevel = _feeLevels[i - 1];
                        IUniswapV3Pool pool = IUniswapV3Pool(IUniswapV3Factory(SWAPFACTORY).getPool(WETH, asset, feeLevel));
                        (, int24 tick, , , , , ) = pool.slot0();
                        int24 tickSpace = pool.tickSpacing();
                        if (currentTicks[i - 1] + tickSpace < tick || currentTicks[i - 1] - tickSpace > tick) {
                            revert HighSlippage();
                        }
                        ISwapRouter(SWAPROUTER).exactInputSingle(
                            ISwapRouter.ExactInputSingleParams({
                                tokenIn: WETH,
                                tokenOut: asset,
                                fee: feeLevel,
                                recipient: address(this),
                                deadline: block.timestamp,
                                amountIn: caps[i],
                                amountOutMinimum: 0,
                                sqrtPriceLimitX96: 0
                            })
                        );
                    }
                }
            }
            _mint(msg.sender, _totalSupply * msg.value / totalCap);
        }
    }

    function removeCapital(uint256 share, int24[TOKENCOUNT] calldata currentTicks) external nonReentrant notLocked(msg.sender) {
        address[TOKENCOUNT] memory assets = [WBTC, UNI, LINK, SOL];
        uint256 _totalSupply = totalSupply();
        IWETH(WETH).withdraw(IWETH(WETH).balanceOf(address(this)));
        uint256 remainBalance = address(this).balance * (_totalSupply - share) / _totalSupply;
        uint24[TOKENCOUNT] memory _feeLevels = feeLevels;
        for (uint256 i = 0; i < TOKENCOUNT; i++) {
            uint24 feeLevel = _feeLevels[i];
            int24 currentTick = currentTicks[i];
            address asset = assets[i];
            IUniswapV3Pool pool = IUniswapV3Pool(IUniswapV3Factory(SWAPFACTORY).getPool(WETH, asset, feeLevel));
            (, int24 tick, , , , , ) = pool.slot0();
            int24 tickSpace = pool.tickSpacing();
            if (currentTick + tickSpace < tick || currentTick - tickSpace > tick) {
                revert HighSlippage();
            }
            uint256 amount = IERC20(asset).balanceOf(address(this)) * share / _totalSupply;
            if (amount > 0) {
                IERC20(asset).approve(SWAPROUTER, 0);
                IERC20(asset).approve(SWAPROUTER, amount);
                ISwapRouter(SWAPROUTER).exactInputSingle(
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: asset,
                        tokenOut: WETH,
                        fee: feeLevel,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: amount,
                        amountOutMinimum: 0,
                        sqrtPriceLimitX96: 0
                    })
                );
            }
        }
        IWETH(WETH).withdraw(IWETH(WETH).balanceOf(address(this)));
        _burn(msg.sender, share);
        (bool success, ) = msg.sender.call{value:address(this).balance - remainBalance}("");
        require(success);
    }

    function transfer(address recipient, uint256 amount) public override lock(recipient) returns(bool) {
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override lock(recipient) returns(bool) {
        return super.transferFrom(sender, recipient, amount);
    }

    receive() external payable {

    }
}
