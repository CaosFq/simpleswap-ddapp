// SPDX-License-Identifier: MIT
pragma solidity >=0.8.2 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ERC20Mock is ERC20, Ownable {
    // Constructor actualizado para pasar el owner inicial
    constructor(string memory name_, string memory symbol_) 
        ERC20(name_, symbol_)
        Ownable(msg.sender)  // Aquí está la correción clave
    {}

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
}