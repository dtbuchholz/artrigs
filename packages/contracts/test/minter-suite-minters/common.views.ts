import { constants, expectRevert } from "@openzeppelin/test-helpers";
import { expect } from "chai";
import { loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import {
  T_Config,
  deployCoreWithMinterFilter,
  deployAndGet,
} from "../util/common";

/**
 * These tests are intended to check common views Minter functionality
 * for minters in our minter suite.
 * @dev assumes common BeforeEach to populate accounts, constants, and setup
 */
export const Common_Views = async (_beforeEach: () => Promise<T_Config>) => {
  describe("projectMaxHasBeenInvoked", async function () {
    it("should return false if project has not yet been minted out", async function () {
      const config = await loadFixture(_beforeEach);
      let result = await config.minter.projectMaxHasBeenInvoked(
        config.projectZero,
        config.genArt721Core.address
      );
      expect(result).to.equal(false);
    });
  });

  describe("projectMaxInvocations", async function () {
    it("should return proper response when not set", async function () {
      const config = await loadFixture(_beforeEach);
      let result = await config.minter.projectMaxInvocations(
        config.projectZero,
        config.genArt721Core.address
      );
      expect(result).to.equal(0);
    });

    it("should return proper response when set", async function () {
      const config = await loadFixture(_beforeEach);
      await config.minter
        .connect(config.accounts.artist)
        .manuallyLimitProjectMaxInvocations(
          config.projectZero,
          config.genArt721Core.address,
          1
        );
      let result = await config.minter.projectMaxInvocations(
        config.projectZero,
        config.genArt721Core.address
      );
      expect(result).to.equal(1);
    });
  });

  describe("currency info hooks", async function () {
    const unconfiguredProjectNumber = 99;

    it("reports expected price per token", async function () {
      const config = await loadFixture(_beforeEach);
      // returns zero for unconfigured project price
      const currencyInfo = await config.minter
        .connect(config.accounts.artist)
        .getPriceInfo(unconfiguredProjectNumber, config.genArt721Core.address);
      expect(currencyInfo.tokenPriceInWei).to.be.equal(0);
    });

    it("reports expected isConfigured", async function () {
      const config = await loadFixture(_beforeEach);
      let currencyInfo = await config.minter
        .connect(config.accounts.artist)
        .getPriceInfo(config.projectOne, config.genArt721Core.address);
      expect(currencyInfo.isConfigured).to.be.equal(true);
      // false for unconfigured project
      currencyInfo = await config.minter
        .connect(config.accounts.artist)
        .getPriceInfo(unconfiguredProjectNumber, config.genArt721Core.address);
      expect(currencyInfo.isConfigured).to.be.equal(false);
    });

    it("reports currency as ETH", async function () {
      const config = await loadFixture(_beforeEach);
      const priceInfo = await config.minter
        .connect(config.accounts.artist)
        .getPriceInfo(config.projectZero, config.genArt721Core.address);
      expect(priceInfo.currencySymbol).to.be.equal("ETH");
    });

    it("reports currency address as null address", async function () {
      const config = await loadFixture(_beforeEach);
      const priceInfo = await config.minter
        .connect(config.accounts.artist)
        .getPriceInfo(config.projectZero, config.genArt721Core.address);
      expect(priceInfo.currencyAddress).to.be.equal(constants.ZERO_ADDRESS);
    });
  });

  describe("isEngineView", async function () {
    it("correctly reports isEngine", async function () {
      const config = await loadFixture(_beforeEach);
      const isEngineView = await config.minter
        .connect(config.accounts.artist)
        .isEngineView(config.genArt721Core.address);
      expect(isEngineView).to.be.equal(config.isEngine);
    });

    it("reverts if invalid core contract", async function () {
      const config = await loadFixture(_beforeEach);
      const coreContractName = "GenArt721CoreV3_Engine_IncorrectCoreType";

      // deploying random (invalid) core contract
      const { genArt721Core } = await deployCoreWithMinterFilter(
        config,
        coreContractName,
        "MinterFilterV1"
      );

      expectRevert(
        config.minter
          .connect(config.accounts.artist)
          .isEngineView(genArt721Core.address),
        "Unexpected revenue split bytes"
      );
    });
  });

  describe("projectConfig", async function () {
    it("should return proper response when set", async function () {
      const config = await loadFixture(_beforeEach);
      await config.minter
        .connect(config.accounts.artist)
        .updatePricePerTokenInWei(
          config.projectZero,
          config.genArt721Core.address,
          config.pricePerTokenInWei
        );
      const projectConfig = await config.minter
        .connect(config.accounts.artist)
        .projectConfig(config.projectZero, config.genArt721Core.address);

      expect(projectConfig.pricePerTokenInWei).to.equal(
        config.pricePerTokenInWei
      );
      expect(projectConfig.priceIsConfigured).to.equal(true);
    });
    it("should return proper response when not set", async function () {
      const config = await loadFixture(_beforeEach);

      const projectConfig = await config.minter
        .connect(config.accounts.artist)
        .projectConfig(config.projectZero, config.genArt721Core.address);

      expect(projectConfig.pricePerTokenInWei).to.equal(constants.ZERO_BYTES32);
      expect(projectConfig.priceIsConfigured).to.equal(false);
    });
  });
};
