const { expect } = require("chai");
const { ethers } = require("hardhat");

async function increaseTime(seconds) {
  await ethers.provider.send("evm_increaseTime", [seconds]);
  await ethers.provider.send("evm_mine", []);
}

async function sustainDepeg24h({ feed, oracle, stable }) {
  for (let i = 0; i < 24; i++) {
    await feed.setAnswer(85000000);
    await oracle.update(stable.address);
    await increaseTime(3600 + 1);
  }
}

async function expectRevert(promise, contains) {
  try {
    await promise;
    expect.fail("Expected revert, but tx succeeded");
  } catch (e) {
    const msg = (e && e.message) ? e.message : String(e);
    if (contains) expect(msg).to.include(contains);
  }
}

describe("DePegGuard - end-to-end", function () {
  async function deployFixture() {
    const [deployer, attacker, lp, user] = await ethers.getSigners();

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const stable = await MockERC20.deploy("Mock USD", "mUSD", 18);
    await stable.deployed();

    const MockV3 = await ethers.getContractFactory("MockV3Aggregator");
    const feed = await MockV3.deploy(8, 100000000);
    await feed.deployed();

    const OracleAdapter = await ethers.getContractFactory("OracleAdapter");
    const oracle = await OracleAdapter.deploy();
    await oracle.deployed();

    const InsurancePool = await ethers.getContractFactory("InsurancePool");
    const pool = await InsurancePool.deploy(stable.address);
    await pool.deployed();

    const CoverNFT = await ethers.getContractFactory("CoverNFT");
    const nft = await CoverNFT.deploy(ethers.constants.AddressZero);
    await nft.deployed();

    const DepegGuardCore = await ethers.getContractFactory("DepegGuardCore");
    const core = await DepegGuardCore.deploy(nft.address, pool.address, oracle.address);
    await core.deployed();

    await nft.setCore(core.address);
    await pool.setCore(core.address);
    await oracle.setNFTContract(nft.address);
    await oracle.setCore(core.address);
    await oracle.setPriceFeed(stable.address, feed.address);

    const lpDeposit = ethers.utils.parseEther("1000");
    await stable.mint(lp.address, lpDeposit);
    await stable.connect(lp).approve(pool.address, lpDeposit);
    await pool.connect(lp).depositLiquidity(lpDeposit);

    return { deployer, attacker, lp, user, stable, feed, oracle, pool, nft, core };
  }

  it("1) LP deposit works and liquidity is real", async function () {
    const { pool } = await deployFixture();
    const liq = await pool.availableLiquidity();
    expect(liq.toString()).to.equal(ethers.utils.parseEther("1000").toString());
  });

  it("2) registerDepeg is gated (onlyOwner)", async function () {
    const { core, attacker, stable, feed, oracle } = await deployFixture();
    await feed.setAnswer(85000000);
    await oracle.update(stable.address);
    await increaseTime(24 * 3600 + 2);
    await feed.setAnswer(85000000);
    await oracle.update(stable.address);
    await expectRevert(
      core.connect(attacker).registerDepeg(stable.address, 1),
      "Not owner"
    );
  });

  it("3) cannot register when no depeg confirmed", async function () {
    const { core, stable } = await deployFixture();
    await expectRevert(core.registerDepeg(stable.address, 1), "No depeg");
  });

  it("4) can register after depeg window (Moderate=24h)", async function () {
    const { core, stable, feed, oracle } = await deployFixture();
    await sustainDepeg24h({ feed, oracle, stable });
    await core.registerDepeg(stable.address, 1);
    expect(true).to.equal(true);
  });

  it("5) settleEvent cannot be empty/incorrect list (prevents griefing)", async function () {
    const { core, stable, feed, oracle } = await deployFixture();
    await sustainDepeg24h({ feed, oracle, stable });
    await core.registerDepeg(stable.address, 1);
    await expectRevert(core.settleEvent(0, []), "Empty token list");
    await expectRevert(core.settleEvent(0, [9999]), "No eligible policies");
  });

  it("6) pro-rata scaling works when pool liquidity is insufficient", async function () {
    const { core, stable, feed, oracle, pool, user } = await deployFixture();
    const coverage = ethers.utils.parseEther("2000");
    await core.mintPolicy(user.address, stable.address, coverage, 7 * 24 * 3600, 1);
    await core.mintPolicy(user.address, stable.address, coverage, 7 * 24 * 3600, 1);
    await sustainDepeg24h({ feed, oracle, stable });
    await core.registerDepeg(stable.address, 1);
    const before = await stable.balanceOf(user.address);
    await core.settleEvent(0, [0, 1]);
    const after = await stable.balanceOf(user.address);
    expect(after.gt(before)).to.equal(true);
    const liqAfter = await pool.availableLiquidity();
    expect(liqAfter.lt(ethers.utils.parseEther("1000"))).to.equal(true);
  });
});
