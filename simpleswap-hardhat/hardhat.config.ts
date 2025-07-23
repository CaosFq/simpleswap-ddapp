import * as dotenv from "dotenv";
dotenv.config(); // Asegura que las variables del .env se carguen

import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-ethers"; // Para interactuar con Ethereum
import "@nomicfoundation/hardhat-chai-matchers"; // Para pruebas
import "@typechain/hardhat"; // Para generar tipos de TypeScript
import "hardhat-gas-reporter"; // Para reportar uso de gas
import "solidity-coverage"; // Para cobertura de código
import "@nomicfoundation/hardhat-verify"; // Para verificar contratos en exploradores
import "hardhat-deploy"; // Para el sistema de despliegue
import "hardhat-deploy-ethers"; // Utilidades de ethers para hardhat-deploy

// Si no se establece, usa la clave privada de la cuenta 0 de Hardhat.
// Puedes generar una cuenta aleatoria con `yarn generate` o `yarn account:import` para importar tu PK existente
const deployerPrivateKey =
  process.env.__RUNTIME_DEPLOYER_PRIVATE_KEY ??
  "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"; // <--- ESTO ES UN VALOR POR DEFECTO. ¡Asegúrate de que tu .env sobrescriba esto con tu clave REAL!

// Si no se establece, usa las claves API por defecto de nuestros exploradores de bloques.
const etherscanApiKey =
  process.env.ETHERSCAN_V2_API_KEY || "DNXJA8RX2Q3VZ4URQIWP7Z68CJXQZSC6AW"; // <--- Clave para Etherscan (si necesitas verificar contratos)

// Si no se establece, usa la clave API por defecto de Alchemy.
// Puedes obtener la tuya en https://dashboard.alchemyapi.io
const providerApiKey =
  process.env.ALCHEMY_API_KEY || "oKxs-03sij-U_N0iOlrSsZFr29-IqbuF"; // <--- ESTO ES UN VALOR POR DEFECTO. ¡Asegúrate de que tu .env sobrescriba esto con tu clave REAL de Alchemy/Infura!

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: "0.8.20", // La versión de Solidity que estás usando
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  defaultNetwork: "hardhat", // Puedes dejarlo en hardhat para desarrollo local, o cambiarlo a "sepolia" para pruebas directas en Sepolia.
  namedAccounts: {
    deployer: {
      default: 0, // Por defecto, toma la primera cuenta de Hardhat como el desplegador
    },
  },
  networks: {
    // Configuración para la red Hardhat local (usada para forking o simulación)
    hardhat: {
      chainId: 31337, // Importante: Scaffold-ETH 2 usa 31337 para hardhat. Si la cambiaste a 1337 antes, cámbiala a 31337.
      // Puedes comentar o eliminar el forking si no lo usas para simplificar.
      // forking: {
      //   url: `https://eth-mainnet.alchemyapi.io/v2/${providerApiKey}`,
      //   enabled: process.env.MAINNET_FORKING_ENABLED === "true",
      // },
    },
    // Configuración para el Hardhat local (cuando ejecutas npx hardhat node)
    localhost: {
      chainId: 31337, // El chainId que usa tu nodo local
      url: "http://localhost:8545", // La dirección de tu nodo local
    },
    // --- Configuración para la red Sepolia (¡la que necesitamos!) ---
    sepolia: {
      url: `https://eth-sepolia.g.alchemy.com/v2/${providerApiKey}`, // <--- Usará tu ALCHEMY_API_KEY del .env
      accounts: [deployerPrivateKey], // <--- Usará tu __RUNTIME_DEPLOYER_PRIVATE_KEY del .env
      chainId: 11155111, // Chain ID de Sepolia
    },
    // --- Puedes añadir otras redes si las necesitas en el futuro ---
    // Por ejemplo, otras testnets o mainnets
    // goerli: {
    //   url: `https://eth-goerli.alchemyapi.io/v2/${providerApiKey}`,
    //   accounts: [deployerPrivateKey],
    //   chainId: 5,
    // },
    // mainnet: {
    //   url: `https://eth-mainnet.alchemyapi.io/v2/${providerApiKey}`,
    //   accounts: [deployerPrivateKey],
    //   chainId: 1,
    // },
  },
  // Configuración para hardhat-verify plugin (para verificar contratos en Etherscan)
  etherscan: {
    apiKey: `${etherscanApiKey}`,
  },
  // Configuración para etherscan-verify desde hardhat-deploy plugin
  verify: {
    etherscan: {
      apiKey: `${etherscanApiKey}`,
    },
  },
  sourcify: {
    enabled: false, // Desactiva Sourcify si no lo usas
  },
  typechain: {
    outDir: "typechain-types",
    target: "ethers-v6",
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
};

export default config;
