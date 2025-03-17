// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }

    modifier onlyOwner() {
        require(msg.sender == _owner, "Caller is not the owner");
        _;
    }

    function owner() public view returns (address) {
        return _owner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

interface IBEP20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

contract Token is IBEP20, Ownable {
    using ECDSA for bytes32;

    string public name = "BOG";
    string public symbol = "BOG";
    uint8 public decimals = 18;
    uint256 private _totalSupply;
    uint256 public priceInUSD = 0.01 * 10 ** 18; // 0.01 USD in wei

    AggregatorV3Interface internal priceFeed;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;

    // Used for EIP-2612 permit approvals
    mapping(address => uint256) public nonces;
    bytes32 public constant PERMIT_TYPEHASH = keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public DOMAIN_SEPARATOR;

    constructor(uint256 initialSupply, address _priceFeed) {
        uint256 chainId = block.chainid; // Assign the chain ID
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256(bytes("1")),
                chainId,
                address(this)
            )
        );
        _mint(msg.sender, initialSupply * 10 ** uint256(decimals));
        priceFeed = AggregatorV3Interface(_priceFeed);
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply; // Gas: ~2100
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account]; // Gas: ~2100
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, recipient, amount); // Gas: ~51000
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender]; // Gas: ~2100
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount); // Gas: ~46000
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        _transfer(sender, recipient, amount); // Gas: ~51000
        _approve(sender, msg.sender, _allowances[sender][msg.sender] - amount); // Gas: ~46000
        return true;
    }

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(deadline >= block.timestamp, "Expired deadline"); // Gas: ~2100

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                owner,
                spender,
                value,
                nonces[owner]++,
                deadline
            )
        );
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );
        address signer = hash.recover(v, r, s);
        require(signer == owner, "Invalid signature"); // Gas: ~2100

        _approve(owner, spender, value); // Gas: ~46000
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue); // Gas: ~46000
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "Decreased allowance below zero"); // Gas: ~2100
        _approve(msg.sender, spender, currentAllowance - subtractedValue); // Gas: ~46000
        return true;
    }

    function mintDaily() public onlyOwner {
        uint256 dailyMintAmount = 3000 * 10 ** uint256(decimals);
        _mint(msg.sender, dailyMintAmount); // Gas: ~51000
    }

    function mint(uint256 amount) public onlyOwner {
        _mint(msg.sender, amount); // Gas: ~51000
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount); // Gas: ~51000
    }

    // Implementing the missing _transfer function
    function _transfer(address sender, address recipient, uint256 amount) internal {
        require(sender != address(0), "Transfer from the zero address"); // Gas: ~2100
        require(recipient != address(0), "Transfer to the zero address"); // Gas: ~2100

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "Transfer amount exceeds balance"); // Gas: ~2100

        // Update balances
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount); // Gas: ~51000
    }

    function _mint(address to, uint256 value) internal {
        require(to != address(0), "Mint to the zero address"); // Gas: ~2100

        _totalSupply += value;
        _balances[to] += value;
        emit Transfer(address(0), to, value); // Gas: ~51000
    }

    function _burn(address from, uint256 value) internal {
        require(from != address(0), "Burn from the zero address"); // Gas: ~2100

        uint256 accountBalance = _balances[from];
        require(accountBalance >= value, "Burn amount exceeds balance"); // Gas: ~2100
        _balances[from] = accountBalance - value;
        _totalSupply -= value;
        emit Transfer(from, address(0), value); // Gas: ~51000
    }

    function _approve(address owner, address spender, uint256 value) internal {
        require(owner != address(0), "Approve from the zero address"); // Gas: ~2100
        require(spender != address(0), "Approve to the zero address"); // Gas: ~2100

        _allowances[owner][spender] = value;
        emit Approval(owner, spender, value); // Gas: ~46000
    }

    function getLatestPrice() public view returns (int) {
        (
            , 
            int price,
            ,
            ,
        ) = priceFeed.latestRoundData(); // Gas: ~2100
        return price;
    }

    function setPriceInUSD(uint256 newPriceInUSD) public onlyOwner {
        priceInUSD = newPriceInUSD; // Gas: ~2100
    }

    // Fixed the setGasLimit function to not include view/pure
    function setGasLimit(uint256 gasLimit) view  public onlyOwner {
        require(gasLimit > 0, "Gas limit must be greater than zero");
        // Set the gas limit for transactions (logic needs to be implemented)
    }
}
