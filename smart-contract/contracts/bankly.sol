// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ERC20} from "./tokens/ERC20.sol";
import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./utils/FixedPointMathLib.sol";

contract Bankly is ERC20 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    mapping(address => uint256) public shareHolders;

    // Events
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    // Immutables

    ERC20 public immutable asset;

    constructor(ERC20 _asset, string memory _name, string memory _symbol) ERC20(_name, _symbol, _asset.decimals()) {
        asset = _asset;
    }

    // Deposit / Withdrawal logic

    function deposit(uint256 assets_, address receiver) public virtual returns (uint256 shares) {
        require((shares = previewDeposit(assets_)) != 0, "ZERO_SHARES");
        require(assets_ > 0, "Deposit less than Zero");
        require(asset.balanceOf(msg.sender) >= assets_, "Insufficient balance");

        asset.safeTransferFrom(msg.sender, address(this), assets_);

        _mint(receiver, assets_);
    }

    function mint(uint256 shares_, address receiver) public virtual returns (uint256 assets) {
        assets = previewMint(shares_);

        // we need to transfer assets before minting
        asset.safeTransferFrom(msg.sender, address(this), assets);
        emit Deposit(msg.sender, receiver, assets, shares_);

        _mint(receiver, shares_);
    }

    function withdraw(uint256 assets_, address receiver, address owner) public virtual returns (uint256 shares) {
        shares = previewWithdraw(assets_);

        // updating allowance
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; //saves gas for limited approvals
            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - shares;
            }
        }

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets_, shares);
        asset.safeTransfer(receiver, assets_);
    }

    function redeem(uint256 shares_, address receiver, address owner) public virtual returns (uint256 assets) {
        require((assets = previewRedeem(shares_)) != 0, "ZERO_ASSETS");
        // require(balanceOf(owner) >= shares_, "Insufficient balance"); use share holder mapping instead

        // updating allowance
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; //saves gas for limited approvals
            if (allowed != type(uint256).max) {
                allowance[owner][msg.sender] = allowed - shares_;
            }
        }

        _burn(owner, shares_);
        emit Withdraw(msg.sender, receiver, owner, assets, shares_);
        asset.safeTransfer(receiver, assets);
    }

    //  Accounting logic
    function totalAssets() public view virtual returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function previewDeposit(uint256 assets_) public view virtual returns (uint256) {
        return convertToShares(assets_);
    }

    function convertToShares(uint256 assets_) public view virtual returns (uint256) {
        uint256 supply = totalSupply;

        return supply == 0 ? assets_ : assets_.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 shares_) public view virtual returns (uint256) {
        uint256 supply = totalSupply;

        return supply == 0 ? shares_ : shares_.mulDivDown(totalAssets(), supply);
    }

    function previewMint(uint256 shares_) public view virtual returns (uint256) {
        return convertToAssets(shares_);
    }

    function previewRedeem(uint256 shares_) public view virtual returns (uint256) {
        return convertToAssets(shares_);
    }

    function previewWithdraw(uint256 assets_) public view virtual returns (uint256) {
        uint256 supply = totalSupply;

        return supply == 0 ? assets_ : assets_.mulDivUp(supply, totalAssets());
    }
}
