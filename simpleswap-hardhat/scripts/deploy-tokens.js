async function main() {
  const Token = await ethers.getContractFactory("ERC20Mock");
  const tokenA = await Token.deploy("Token A", "TKA");
  const tokenB = await Token.deploy("Token B", "TKB");

  console.log("Token A desplegado en:", tokenA.address);
  console.log("Token B desplegado en:", tokenB.address);
}