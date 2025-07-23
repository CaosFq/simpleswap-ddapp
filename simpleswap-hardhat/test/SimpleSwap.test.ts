import { loadFixture, time } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";
import type { SimpleSwap, ERC20Mock } from "../typechain-types";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";

describe("SimpleSwap", function () {
  async function deployContractsFixture() {
    const [owner, user1, user2] = await ethers.getSigners();

    // Deploy mock tokens
    const ERC20Mock = await ethers.getContractFactory("ERC20Mock");
    const tokenA = (await ERC20Mock.deploy("TokenA", "TKA")) as ERC20Mock;
    const tokenB = (await ERC20Mock.deploy("TokenB", "TKB")) as ERC20Mock;

    // Deploy SimpleSwap
    const SimpleSwap = await ethers.getContractFactory("SimpleSwap");
    const simpleSwap = (await SimpleSwap.deploy(
      await tokenA.getAddress(),
      await tokenB.getAddress()
    )) as SimpleSwap;

    // Mint initial tokens
    const initialSupply = ethers.parseEther("1000000");
    await tokenA.mint(owner.address, initialSupply);
    await tokenB.mint(owner.address, initialSupply);
    await tokenA.mint(user1.address, initialSupply);
    await tokenB.mint(user1.address, initialSupply);
    await tokenA.mint(user2.address, initialSupply);
    await tokenB.mint(user2.address, initialSupply);

    // Approve transfers
    const maxApprove = ethers.MaxUint256;
    await tokenA.connect(owner).approve(simpleSwap.target, maxApprove);
    await tokenB.connect(owner).approve(simpleSwap.target, maxApprove);
    await tokenA.connect(user1).approve(simpleSwap.target, maxApprove);
    await tokenB.connect(user1).approve(simpleSwap.target, maxApprove);
    await tokenA.connect(user2).approve(simpleSwap.target, maxApprove);
    await tokenB.connect(user2).approve(simpleSwap.target, maxApprove);

    return { simpleSwap, tokenA, tokenB, owner, user1, user2 };
  }

  describe("Deployment", function () {
    it("1. Should deploy with correct token addresses", async function () {
      const { simpleSwap, tokenA, tokenB } = await loadFixture(deployContractsFixture);
      
      const token0 = await simpleSwap.token0();
      const token1 = await simpleSwap.token1();
      const tokens = [await tokenA.getAddress(), await tokenB.getAddress()].sort();
      
      expect(token0).to.equal(tokens[0]);
      expect(token1).to.equal(tokens[1]);
    });

    it("2. Should have zero reserves initially", async function () {
      const { simpleSwap } = await loadFixture(deployContractsFixture);
      
      expect(await simpleSwap.reserve0()).to.equal(0);
      expect(await simpleSwap.reserve1()).to.equal(0);
    });
  });

  describe("Add Liquidity", function () {
    it("3. Should add liquidity successfully", async function () {
      const { simpleSwap, tokenA, tokenB, owner } = await loadFixture(deployContractsFixture);
      const deadline = (await time.latest()) + 300;
      
      await simpleSwap.addLiquidity(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        ethers.parseEther("100"),
        ethers.parseEther("200"),
        0,
        0,
        owner.address,
        deadline
      );
      
      expect(await simpleSwap.reserve0()).to.be.gt(0);
      expect(await simpleSwap.reserve1()).to.be.gt(0);
      expect(await simpleSwap.totalLiquidity()).to.be.gt(0);
    });

    it("4. Should emit AddLiquidity event", async function () {
      const { simpleSwap, tokenA, tokenB, owner } = await loadFixture(deployContractsFixture);
      const deadline = (await time.latest()) + 300;
      
      await expect(
        simpleSwap.addLiquidity(
          await tokenA.getAddress(),
          await tokenB.getAddress(),
          ethers.parseEther("100"),
          ethers.parseEther("200"),
          0,
          0,
          owner.address,
          deadline
        )
      )
        .to.emit(simpleSwap, "AddLiquidity")
        .withArgs(owner.address, anyValue, anyValue, anyValue);
    });
  });

  describe("Swap Tokens", function () {
    it("5. Should calculate correct output amount", async function () {
      const { simpleSwap, tokenA, tokenB, owner, user1 } = await loadFixture(deployContractsFixture);
      const deadline = (await time.latest()) + 300;
      
      // Add liquidity
      await simpleSwap.connect(owner).addLiquidity(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        ethers.parseEther("1000"),
        ethers.parseEther("2000"),
        0,
        0,
        owner.address,
        deadline
      );
      
      const amountIn = ethers.parseEther("10");
      const path = [await tokenA.getAddress(), await tokenB.getAddress()];
      
      // Get reserves
      const reserveIn = await simpleSwap.reserve0();
      const reserveOut = await simpleSwap.reserve1();
      
      // Calculate expected output
      const expectedOut = await simpleSwap.getAmountOut(amountIn, reserveIn, reserveOut);
      
      // Perform swap and measure actual output
      const balanceBefore = await tokenB.balanceOf(user1.address);
      await simpleSwap.connect(user1).swapExactTokensForTokens(
        amountIn,
        0,
        path,
        user1.address,
        deadline
      );
      const balanceAfter = await tokenB.balanceOf(user1.address);
      
      // Verify only the output amount
      expect(balanceAfter - balanceBefore).to.equal(expectedOut);
    });

    it("6. Should emit Swap event", async function () {
      const { simpleSwap, tokenA, tokenB, owner, user1 } = await loadFixture(deployContractsFixture);
      const deadline = (await time.latest()) + 300;
      
      // Add liquidity
      await simpleSwap.connect(owner).addLiquidity(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        ethers.parseEther("1000"),
        ethers.parseEther("2000"),
        0,
        0,
        owner.address,
        deadline
      );
      
      const amountIn = ethers.parseEther("10");
      const path = [await tokenA.getAddress(), await tokenB.getAddress()];
      
      await expect(
        simpleSwap.connect(user1).swapExactTokensForTokens(
          amountIn,
          0,
          path,
          user1.address,
          deadline
        )
      )
        .to.emit(simpleSwap, "Swap")
        .withArgs(user1.address, amountIn, anyValue, path[0], path[1]);
    });
  });

  describe("Remove Liquidity", function () {
    it("7. Should emit RemoveLiquidity event", async function () {
      const { simpleSwap, tokenA, tokenB, owner } = await loadFixture(deployContractsFixture);
      const deadline = (await time.latest()) + 300;
      
      // Add liquidity
      await simpleSwap.addLiquidity(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        ethers.parseEther("500"),
        ethers.parseEther("1000"),
        0,
        0,
        owner.address,
        deadline
      );
      
      const liquidity = await simpleSwap.liquidityBalances(owner.address);
      
      await expect(
        simpleSwap.removeLiquidity(
          await tokenA.getAddress(),
          await tokenB.getAddress(),
          liquidity,
          0,
          0,
          owner.address,
          deadline
        )
      )
        .to.emit(simpleSwap, "RemoveLiquidity")
        .withArgs(owner.address, anyValue, anyValue, liquidity);
    });

    it("8. Should return correct token amounts when removing liquidity", async function () {
      const { simpleSwap, tokenA, tokenB, owner } = await loadFixture(deployContractsFixture);
      const deadline = (await time.latest()) + 300;
      
      // Add liquidity
      const amountA = ethers.parseEther("500");
      const amountB = ethers.parseEther("1000");
      await simpleSwap.addLiquidity(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        amountA,
        amountB,
        0,
        0,
        owner.address,
        deadline
      );
      
      const liquidity = await simpleSwap.liquidityBalances(owner.address);
      const totalLiquidity = await simpleSwap.totalLiquidity();
      
      // Remove half liquidity
      const amountToRemove = liquidity / 2n;
      
      // Calculate expected token amounts
      const reserve0 = await simpleSwap.reserve0();
      const reserve1 = await simpleSwap.reserve1();
      const expectedAmount0 = (amountToRemove * reserve0) / totalLiquidity;
      const expectedAmount1 = (amountToRemove * reserve1) / totalLiquidity;
      
      // Perform removal
      const tx = await simpleSwap.removeLiquidity(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        amountToRemove,
        0,
        0,
        owner.address,
        deadline
      );
      
      // Get actual token amounts from event
      const receipt = await tx.wait();
      const event = receipt?.logs?.find((log) => 
        log instanceof ethers.EventLog && log.fragment.name === "RemoveLiquidity"
      ) as ethers.EventLog;
      
      const [actualAmount0, actualAmount1] = event?.args.slice(1, 3) || [];
      
      // Verify amounts
      expect(actualAmount0).to.be.closeTo(expectedAmount0, expectedAmount0 / 100n);
      expect(actualAmount1).to.be.closeTo(expectedAmount1, expectedAmount1 / 100n);
    });
  });

  describe("Edge Cases", function () {
    it("9. Should handle very large swaps", async function () {
      const { simpleSwap, tokenA, tokenB, user1 } = await loadFixture(deployContractsFixture);
      const deadline = (await time.latest()) + 300;
      
      // Add substantial liquidity
      const reserveA = ethers.parseEther("100000");
      const reserveB = ethers.parseEther("200000");
      await simpleSwap.connect(user1).addLiquidity(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        reserveA,
        reserveB,
        0,
        0,
        user1.address,
        deadline
      );
      
      // Perform large swap (10% of pool)
      const amountIn = ethers.parseEther("10000");
      const path = [await tokenA.getAddress(), await tokenB.getAddress()];
      
      // Calculate expected output
      const expectedOut = await simpleSwap.getAmountOut(
        amountIn,
        reserveA,
        reserveB
      );
      
      // Perform swap
      const balanceBefore = await tokenB.balanceOf(user1.address);
      await simpleSwap.connect(user1).swapExactTokensForTokens(
        amountIn,
        expectedOut * 99n / 100n,
        path,
        user1.address,
        deadline
      );
      const balanceAfter = await tokenB.balanceOf(user1.address);
      
      const outputAmount = balanceAfter - balanceBefore;
      
      // Verify output
      expect(outputAmount).to.be.closeTo(
        expectedOut, 
        expectedOut / 100n
      );
    });

    it("10. Should maintain constant product invariant after multiple operations", async function () {
      const { simpleSwap, tokenA, tokenB, owner, user1 } = await loadFixture(deployContractsFixture);
      const deadline = (await time.latest()) + 3000;

      // Utility function for shuffling
      function shuffleArray(array: any[]) {
        for (let i = array.length - 1; i > 0; i--) {
          const j = Math.floor(Math.random() * (i + 1));
          [array[i], array[j]] = [array[j], array[i]];
        }
        return array;
      }

      // Add initial liquidity
      await simpleSwap.connect(owner).addLiquidity(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        ethers.parseEther("1000"),
        ethers.parseEther("2000"),
        0,
        0,
        owner.address,
        deadline
      );

      // Get initial reserves and product
      const initialReserve0 = await simpleSwap.reserve0();
      const initialReserve1 = await simpleSwap.reserve1();
      const initialK = initialReserve0 * initialReserve1;

      // Define operations
      const operations = [
        // Swap 1: TokenA -> TokenB
        async () => {
          await simpleSwap.connect(user1).swapExactTokensForTokens(
            ethers.parseEther("10"),
            0,
            [await tokenA.getAddress(), await tokenB.getAddress()],
            user1.address,
            deadline
          );
        },
        // Add more liquidity
        async () => {
          await simpleSwap.connect(owner).addLiquidity(
            await tokenA.getAddress(),
            await tokenB.getAddress(),
            ethers.parseEther("100"),
            ethers.parseEther("200"),
            0,
            0,
            owner.address,
            deadline
          );
        },
        // Swap 2: TokenB -> TokenA
        async () => {
          await simpleSwap.connect(user1).swapExactTokensForTokens(
            ethers.parseEther("5"),
            0,
            [await tokenB.getAddress(), await tokenA.getAddress()],
            user1.address,
            deadline
          );
        }
      ];

      // Execute operations
      for (const op of shuffleArray(operations)) {
        await op();
      }

      // Get final reserves and product
      const finalReserve0 = await simpleSwap.reserve0();
      const finalReserve1 = await simpleSwap.reserve1();
      const finalK = finalReserve0 * finalReserve1;

      // Verify K has increased
      expect(finalK).to.be.gt(initialK);
    });
  });

  describe("Price Functionality", function () {
    it("11. Should return correct price based on reserves", async function () {
      const { simpleSwap, tokenA, tokenB, owner } = await loadFixture(deployContractsFixture);
      const deadline = (await time.latest()) + 300;

      // Add liquidity
      await simpleSwap.addLiquidity(
        await tokenA.getAddress(),
        await tokenB.getAddress(),
        ethers.parseEther("1000"),
        ethers.parseEther("2000"),
        0,
        0,
        owner.address,
        deadline
      );

      // Get addresses
      const token0Addr = await simpleSwap.token0();
      const token1Addr = await simpleSwap.token1();

      // Calculate expected prices
      const reserve0 = await simpleSwap.reserve0();
      const reserve1 = await simpleSwap.reserve1();
      
      // Price of token0 in terms of token1
      const expectedPrice0 = (reserve1 * ethers.parseEther("1")) / reserve0;
      
      // Price of token1 in terms of token0
      const expectedPrice1 = (reserve0 * ethers.parseEther("1")) / reserve1;

      // Verify prices match
      expect(await simpleSwap.getPrice(token0Addr, token1Addr)).to.equal(expectedPrice0);
      expect(await simpleSwap.getPrice(token1Addr, token0Addr)).to.equal(expectedPrice1);
    });

    it("12. Should revert for invalid token pairs in getPrice", async function () {
      const { simpleSwap, tokenA } = await loadFixture(deployContractsFixture);
      const fakeToken = ethers.Wallet.createRandom().address;

      // Test with invalid token pair
      await expect(simpleSwap.getPrice(tokenA.target, fakeToken))
        .to.be.revertedWith("SimpleSwap: INVALID_TOKEN_PAIR");
    });

    describe("Additional Coverage Tests", function () {
      it("13. Should handle tokenB as token0 in swap calculation", async function () {
        const { simpleSwap, tokenA, tokenB, user1 } = await loadFixture(deployContractsFixture);
        const deadline = (await time.latest()) + 300;
        
        // Get addresses
        const tokenAAddr = await tokenA.getAddress();
        const tokenBAddr = await tokenB.getAddress();
        const token0Addr = await simpleSwap.token0();
        
        // Create new contract if needed
        let swapContract = simpleSwap;
        
        if (token0Addr !== tokenBAddr) {
          const SimpleSwapFactory = await ethers.getContractFactory("SimpleSwap");
          swapContract = (await SimpleSwapFactory.deploy(
            tokenBAddr,
            tokenAAddr
          )) as SimpleSwap;
          
          // Mint and approve tokens for new contract
          await tokenB.connect(user1).approve(swapContract.target, ethers.MaxUint256);
          await tokenA.connect(user1).approve(swapContract.target, ethers.MaxUint256);
          
          // Add liquidity to new contract
          await swapContract.connect(user1).addLiquidity(
            tokenBAddr,
            tokenAAddr,
            ethers.parseEther("1000"),
            ethers.parseEther("2000"),
            0,
            0,
            user1.address,
            deadline
          );
        }
        
        // Perform swap
        const path = [tokenBAddr, tokenAAddr];
        await expect(
          swapContract.connect(user1).swapExactTokensForTokens(
            ethers.parseEther("10"),
            0,
            path,
            user1.address,
            deadline
          )
        ).to.emit(swapContract, "Swap");
      });

      it("14. Should revert when adding liquidity with insufficient amounts", async function () {
        const { simpleSwap, tokenA, tokenB, owner } = await loadFixture(deployContractsFixture);
        const deadline = (await time.latest()) + 300;
        
        // First liquidity addition
        await simpleSwap.addLiquidity(
          await tokenA.getAddress(),
          await tokenB.getAddress(),
          ethers.parseEther("100"),
          ethers.parseEther("200"),
          0,
          0,
          owner.address,
          deadline
        );

        // Attempt to add with insufficient amounts
        await expect(
          simpleSwap.addLiquidity(
            await tokenA.getAddress(),
            await tokenB.getAddress(),
            ethers.parseEther("50"),
            ethers.parseEther("100"),
            ethers.parseEther("60"), // High minA
            ethers.parseEther("100"),
            owner.address,
            deadline
          )
        ).to.be.revertedWith("SimpleSwap: AMOUNT_0_TOO_LOW");
      });

      it("15. Should revert when removing liquidity with insufficient amounts", async function () {
        const { simpleSwap, tokenA, tokenB, owner } = await loadFixture(deployContractsFixture);
        const deadline = (await time.latest()) + 300;
        
        // Add liquidity
        await simpleSwap.addLiquidity(
          await tokenA.getAddress(),
          await tokenB.getAddress(),
          ethers.parseEther("500"),
          ethers.parseEther("1000"),
          0,
          0,
          owner.address,
          deadline
        );
        
        const liquidity = await simpleSwap.liquidityBalances(owner.address);
        
        // Attempt to remove with high minimums
        await expect(
          simpleSwap.removeLiquidity(
            await tokenA.getAddress(),
            await tokenB.getAddress(),
            liquidity / 2n,
            ethers.parseEther("300"), // High minA
            ethers.parseEther("600"),
            owner.address,
            deadline
          )
        ).to.be.revertedWith("SimpleSwap: INSUFFICIENT_AMOUNT_0_WITHDRAWN");
      });

      it("16. Should handle initial liquidity with minimum amounts", async function () {
        const { simpleSwap, tokenA, tokenB, user2 } = await loadFixture(deployContractsFixture);
        const deadline = (await time.latest()) + 300;
        
        // Attempt to add minimal liquidity (1 wei)
        await expect(
          simpleSwap.connect(user2).addLiquidity(
            await tokenA.getAddress(),
            await tokenB.getAddress(),
            1, // 1 wei
            1, // 1 wei
            0,
            0,
            user2.address,
            deadline
          )
        ).to.be.revertedWith("SimpleSwap: INSUFFICIENT_INITIAL_LIQUIDITY");
      });
      
    });
  });
});