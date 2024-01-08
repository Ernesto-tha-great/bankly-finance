// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import {ERC20} from "./tokens/ERC20.sol";
import {SafeTransferLib} from "./utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "./utils/FixedPointMathLib.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

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
    address public immutable owner;

    constructor(ERC20 _asset, string memory _name, string memory _symbol) ERC20(_name, _symbol, _asset.decimals()) {
        asset = _asset;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function.");

        _;
    }

    // Deposit / Withdrawal logic

    function deposit(uint256 assets_, address receiver) public virtual returns (uint256 shares) {
        require((shares = previewDeposit(assets_)) != 0, "ZERO_SHARES"); //since we round down in previewDeposit, this is a safe check
        require(assets_ > 0, "Deposit less than Zero");
        require(asset.balanceOf(msg.sender) >= assets_, "Insufficient balance");

        asset.safeTransferFrom(msg.sender, address(this), assets_);

        _mint(receiver, shares);
        shareHolders[msg.sender] += shares;
    }

    function mint(uint256 shares_, address receiver) public virtual returns (uint256 assets) {
        require(shares_ > 0, "Mint less than Zero");
        assets = previewMint(shares_); // no need to check for rounding error since we round up

        // we need to transfer assets before minting
        asset.safeTransferFrom(msg.sender, address(this), assets);
        emit Deposit(msg.sender, receiver, assets, shares_);

        _mint(receiver, shares_);
        shareHolders[msg.sender] += shares_;
    }

    function withdraw(uint256 assets_, address receiver, address owner_) public virtual returns (uint256 shares) {
        require(assets_ > 0, "Withdraw less than Zero");
        require(receiver != address(0), "Receiver is Zero");
        require(shareHolders[owner_] >= assets_, "Insufficient balance");
        shares = previewWithdraw(assets_);

        // updating allowance
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; //saves gas for limited approvals
            if (allowed != type(uint256).max) {
                allowance[owner_][msg.sender] = allowed - shares;
            }
        }

        _burn(owner_, shares);
        shareHolders[owner_] -= shares;

        emit Withdraw(msg.sender, receiver, owner_, assets_, shares);
        asset.safeTransfer(receiver, assets_);
    }

    function redeem(uint256 shares_, address receiver, address owner_) public virtual returns (uint256 assets) {
        require((assets = previewRedeem(shares_)) != 0, "ZERO_ASSETS");
        require(shares_ > 0, "Withdraw less than Zero");
        require(receiver != address(0), "Receiver is Zero");
        require(shareHolders[owner_] >= shares_, "Insufficient balance");

        // updating allowance
        if (msg.sender != owner_) {
            uint256 allowed = allowance[owner_][msg.sender]; //saves gas for limited approvals
            if (allowed != type(uint256).max) {
                allowance[owner_][msg.sender] = allowed - shares_;
            }
        }

        _burn(owner_, shares_);
        shareHolders[owner_] -= shares_;
        emit Withdraw(msg.sender, receiver, owner_, assets, shares_);
        asset.safeTransfer(receiver, assets);
    }

    // view functions
    function totalSharesOfUser(address user) public view returns (uint256) {
        return shareHolders[user];
    }

    // investing logic
    function lendOnAave(address aaveV3, uint256 asset_amount) public onlyOwner {
        asset.safeApprove(aaveV3, asset_amount);
        IPool(aaveV3).supply(asset_(), asset_amount, address(this), 0);
    }

    function withdrawFromAave(address aaveV3) public onlyOwner {
        IPool(aaveV3).withdraw(asset_(), type(uint256).max, address(this));
    }

    //  Accounting logic
    function asset_() public view virtual returns (address) {
        return address(asset);
    }

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
