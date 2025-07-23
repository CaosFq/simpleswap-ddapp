async function main() {
  const [deployer] = await ethers.getSigners();
  console.log("Desplegando con la cuenta:", deployer.address);

  // Usa estas direcciones de prueba para desarrollo local
  const tokenA = "0x0000000000000000000000000000000000000001";
  const tokenB = "0x0000000000000000000000000000000000000002";

  const SimpleSwap = await ethers.getContractFactory("SimpleSwap");
  const contract = await SimpleSwap.deploy(tokenA, tokenB); // La línea problemática aquí se resolvió con la eliminación

  console.log("SimpleSwap desplegado en:", contract.address);
}