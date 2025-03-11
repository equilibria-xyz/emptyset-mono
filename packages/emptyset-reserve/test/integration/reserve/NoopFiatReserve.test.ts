import { expect } from 'chai'
import HRE from 'hardhat'
import { constants, utils, BigNumber } from 'ethers'
import {
  NoopFiatReserve,
  NoopFiatReserve__factory,
  IERC20Metadata,
  IERC20Metadata__factory,
  DSU,
  DSU__factory,
} from '../../../types/generated'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { impersonate } from '../../../../common/testutil'
import { reset } from '../../../../common/testutil/time'

const { ethers, deployments, config } = HRE

const USDC_HOLDER_ADDRESS = '0xb38e8c17e38363af6ebdcb3dae12e0243582891d'

describe('NoopFiatReserve', () => {
  let owner: SignerWithAddress
  let user: SignerWithAddress
  let coordinator: SignerWithAddress
  let usdcHolder: SignerWithAddress
  let originalReserveDSU: BigNumber
  let originalReserveUSDC: BigNumber
  let originalOwnerUSDC: BigNumber
  let reserve: NoopFiatReserve
  let dsu: DSU
  let usdc: IERC20Metadata

  const beforeFixture = async () => {
    await reset(config)
    ;[owner, user, coordinator] = await ethers.getSigners()

    dsu = DSU__factory.connect((await deployments.get('DSU')).address, owner)
    usdc = IERC20Metadata__factory.connect((await deployments.get('USDC')).address, owner)

    reserve = await new NoopFiatReserve__factory(owner).deploy(dsu.address, usdc.address)

    // Transfer DSU ownership to new Reserve
    const dsuOwnerSigner = await impersonate.impersonateWithBalance(await dsu.owner(), utils.parseEther('10'))

    await dsu.connect(dsuOwnerSigner).transferOwnership(reserve.address)
    await reserve.initialize()

    await dsu.connect(user).approve(reserve.address, constants.MaxUint256)
    await usdc.connect(user).approve(reserve.address, constants.MaxUint256)

    usdcHolder = await impersonate.impersonateWithBalance(USDC_HOLDER_ADDRESS, utils.parseEther('10'))
    await usdc.connect(usdcHolder).transfer(user.address, 1000e6)

    // initial reserve assets and strategy
    originalReserveDSU = await dsu.totalSupply()
    originalReserveUSDC = originalReserveDSU.sub(1).div(1e12).add(1) // round up to nearest 1e12
    await usdc.connect(usdcHolder).transfer(reserve.address, originalReserveUSDC)
    originalOwnerUSDC = await usdc.balanceOf(owner.address)
  }

  beforeEach(async () => {
    await loadFixture(beforeFixture)
  })

  describe('#constructor', () => {
    it('constructs correctly', async () => {
      expect(await reserve.dsu()).to.equal(dsu.address)
      expect(await reserve.fiat()).to.equal(usdc.address)
    })
  })

  describe('#mintPrice', () => {
    it('returns ONE', async () => {
      expect(await reserve.mintPrice()).to.equal(utils.parseEther('1'))
    })
  })

  describe('#redeemPrice', () => {
    it('returns ONE', async () => {
      expect(await reserve.redeemPrice()).to.equal(utils.parseEther('1'))
    })
  })

  describe('#updateCoordinator', () => {
    it('updates the coordinator address', async () => {
      await expect(reserve.connect(owner).updateCoordinator(coordinator.address))
        .to.emit(reserve, 'CoordinatorUpdated')
        .withArgs(coordinator.address)

      expect(await reserve.coordinator()).to.equal(coordinator.address)
    })

    it('reverts if not owner', async () => {
      await expect(reserve.connect(user).updateCoordinator(coordinator.address)).to.be.revertedWithCustomError(
        reserve,
        'OwnableNotOwnerError',
      )
      expect(await reserve.coordinator()).to.equal(constants.AddressZero)
    })
  })

  describe('#updateAllocation', () => {
    beforeEach(async () => {
      await reserve.connect(owner).updateCoordinator(coordinator.address)
    })

    it('updates the allocation amount', async () => {
      await expect(reserve.connect(coordinator).updateAllocation(utils.parseEther('0.5')))
        .to.emit(reserve, 'AllocationUpdated')
        .withArgs(utils.parseEther('0.5'))

      expect(await reserve.allocation()).to.equal(utils.parseEther('0.5'))
    })

    it('reverts if allocation too large', async () => {
      await expect(
        reserve.connect(coordinator).updateAllocation(utils.parseEther('1').add(1)),
      ).to.be.revertedWithCustomError(reserve, 'ReserveBaseInvalidAllocationError')
      expect(await reserve.allocation()).to.equal(0)
    })

    it('reverts if not coordinator (user)', async () => {
      await expect(reserve.connect(user).updateAllocation(utils.parseEther('0.5'))).to.be.revertedWithCustomError(
        reserve,
        'ReserveBaseNotCoordinatorError',
      )
      expect(await reserve.allocation()).to.equal(0)
    })

    it('reverts if not coordinator (owner)', async () => {
      await expect(reserve.connect(owner).updateAllocation(utils.parseEther('0.5'))).to.be.revertedWithCustomError(
        reserve,
        'ReserveBaseNotCoordinatorError',
      )
      expect(await reserve.allocation()).to.equal(0)
    })
  })

  describe('#mint', () => {
    beforeEach(async () => {
      await reserve.connect(owner).updateCoordinator(coordinator.address)
      await reserve.connect(coordinator).updateAllocation(utils.parseEther('0.5'))
    })

    it('pulls USDC from the sender, wraps it as DSU', async () => {
      const amount = utils.parseEther('10')
      await expect(reserve.connect(user).mint(amount, { gasLimit: 3e6 }))
        .to.emit(usdc, 'Transfer') // USDC pull from user
        .withArgs(user.address, reserve.address, 10e6)
        .to.emit(dsu, 'Transfer') // DSU Mint to Reserve
        .withArgs(constants.AddressZero, reserve.address, amount)
        .to.emit(dsu, 'Transfer') // DSU push from reserve
        .withArgs(reserve.address, user.address, amount)
        .to.emit(reserve, 'Mint') // Reserve Mint
        .withArgs(user.address, amount, amount)

      expect(await reserve.assets()).to.equal(originalReserveUSDC.mul(1e12).add(amount))
      expect(await usdc.balanceOf(user.address)).to.equal(1000e6 - 10e6)
      expect(await dsu.balanceOf(user.address)).to.equal(amount)
      expect(await dsu.totalSupply()).to.equal(originalReserveDSU.add(amount))
    })

    it('pulls USDC from the sender, wraps it as DSU with rounding', async () => {
      const amount = utils.parseEther('10').sub(1)

      await expect(reserve.connect(user).mint(amount))
        .to.emit(usdc, 'Transfer') // USDC pull from user
        .withArgs(user.address, reserve.address, 10e6)
        .to.emit(dsu, 'Transfer') // DSU Mint to Reserve
        .withArgs(constants.AddressZero, reserve.address, amount)
        .to.emit(dsu, 'Transfer') // DSU push from reserve
        .withArgs(reserve.address, user.address, amount)
        .to.emit(reserve, 'Mint') // Reserve Mint
        .withArgs(user.address, amount, amount)

      expect(await reserve.assets()).to.equal(originalReserveUSDC.mul(1e12).add(utils.parseEther('10')))
      expect(await usdc.balanceOf(user.address)).to.equal(1000e6 - 10e6)
      expect(await dsu.balanceOf(user.address)).to.equal(amount)
      expect(await dsu.totalSupply()).to.equal(originalReserveDSU.add(amount))
    })
  })

  describe('#redeem', () => {
    beforeEach(async () => {
      await reserve.connect(owner).updateCoordinator(coordinator.address)
      await reserve.connect(coordinator).updateAllocation(utils.parseEther('0.5'))

      await reserve.connect(user).mint(utils.parseEther('11'))
    })

    it('pulls DSU from the sender, unwraps it to USDC', async () => {
      const amount = utils.parseEther('10')

      await expect(reserve.connect(user).redeem(amount))
        .to.emit(dsu, 'Transfer') // DSU pull from user
        .withArgs(user.address, reserve.address, amount)
        .to.emit(dsu, 'Transfer') // DSU burn
        .withArgs(reserve.address, constants.AddressZero, amount)
        .to.emit(usdc, 'Transfer') // USDC push from reserve
        .withArgs(reserve.address, user.address, 10e6)
        .to.emit(reserve, 'Redeem') // Reserve Redeem
        .withArgs(user.address, amount, amount)

      expect(await reserve.assets()).to.equal(originalReserveUSDC.mul(1e12).add(utils.parseEther('1')))
      expect(await usdc.balanceOf(user.address)).to.equal(1000e6 - 1e6)
      expect(await dsu.balanceOf(user.address)).to.equal(utils.parseEther('1'))
      expect(await dsu.totalSupply()).to.equal(originalReserveDSU.add(utils.parseEther('1')))
    })

    it('pulls DSU from the sender, unwraps it to USDC with roundng', async () => {
      const amount = utils.parseEther('10').add(1)

      await expect(reserve.connect(user).redeem(amount))
        .to.emit(dsu, 'Transfer') // DSU pull from user
        .withArgs(user.address, reserve.address, amount)
        .to.emit(dsu, 'Transfer') // DSU burn
        .withArgs(reserve.address, constants.AddressZero, amount)
        .to.emit(usdc, 'Transfer') // USDC push from reserve
        .withArgs(reserve.address, user.address, 10e6)
        .to.emit(reserve, 'Redeem') // Reserve Redeem
        .withArgs(user.address, amount, amount)

      expect(await reserve.assets()).to.equal(originalReserveUSDC.mul(1e12).add(utils.parseEther('1')))
      expect(await usdc.balanceOf(user.address)).to.equal(1000e6 - 1e6)
      expect(await dsu.balanceOf(user.address)).to.equal(utils.parseEther('11').sub(amount))
      expect(await dsu.totalSupply()).to.equal(originalReserveDSU.add(utils.parseEther('11')).sub(amount))
    })
  })

  describe('#issue', () => {
    it('mints DSU up to collateral requirement', async () => {
      const amount = utils.parseEther('10')
      await usdc.connect(usdcHolder).transfer(reserve.address, amount.div(1e12))

      await expect(reserve.connect(owner).issue(amount))
        .to.emit(dsu, 'Transfer') // DSU push to reserve
        .withArgs(reserve.address, owner.address, amount)
        .to.emit(reserve, 'Issue') // Reserve Issue
        .withArgs(owner.address, amount)

      expect(await reserve.assets()).to.equal(originalReserveUSDC.mul(1e12).add(utils.parseEther('10')))
      expect(await usdc.balanceOf(owner.address)).to.equal(originalOwnerUSDC)
      expect(await dsu.balanceOf(owner.address)).to.equal(utils.parseEther('10'))
      expect(await dsu.totalSupply()).to.equal(originalReserveDSU.add(utils.parseEther('10')))
    })

    it('reverts if under collateral requirement', async () => {
      const amount = utils.parseEther('10')
      await usdc.connect(usdcHolder).transfer(reserve.address, amount.div(1e12))

      await expect(reserve.connect(owner).issue(amount.add(utils.parseEther('1')))).to.be.revertedWithCustomError(
        reserve,
        'ReserveBaseInsufficientAssetsError',
      )
    })

    it('reverts if not owner', async () => {
      const amount = utils.parseEther('10')
      await expect(reserve.connect(user).issue(amount)).to.be.revertedWithCustomError(reserve, 'OwnableNotOwnerError')
    })
  })
})
