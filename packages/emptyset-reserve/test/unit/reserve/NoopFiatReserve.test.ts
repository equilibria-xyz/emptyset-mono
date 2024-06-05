import { FakeContract, smock } from '@defi-wonderland/smock'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'
import { expect, use } from 'chai'
import { utils, constants } from 'ethers'
import HRE from 'hardhat'
import { DSU, IERC20Metadata, NoopFiatReserve, NoopFiatReserve__factory } from '../../../types/generated'
import { impersonate } from '../../../../common/testutil'

const { ethers } = HRE
use(smock.matchers)

describe('NoopFiatReserve', () => {
  let owner: SignerWithAddress
  let user: SignerWithAddress
  let coordinator: SignerWithAddress
  let reserve: NoopFiatReserve
  let usdc: FakeContract<IERC20Metadata>
  let dsu: FakeContract<DSU>

  beforeEach(async () => {
    ;[owner, user, coordinator] = await ethers.getSigners()

    usdc = await smock.fake<IERC20Metadata>('IERC20Metadata')
    dsu = await smock.fake<DSU>('DSU')

    dsu.decimals.returns(18)
    usdc.decimals.returns(6)

    reserve = await new NoopFiatReserve__factory(owner).deploy(dsu.address, usdc.address)
  })

  describe('#constructor', () => {
    it('constructs correctly', async () => {
      expect(await reserve.dsu()).to.equal(dsu.address)
      expect(await reserve.fiat()).to.equal(usdc.address)
    })
  })

  describe('#initialize', () => {
    it('does nothing if already DSU owner', async () => {
      dsu.owner.returns(reserve.address)
      await expect(reserve.initialize()).to.not.be.reverted
    })

    it('does nothing if already has owner', async () => {
      const zeroAddressSigner = await impersonate.impersonateWithBalance(constants.AddressZero, utils.parseEther('10'))

      await reserve.connect(zeroAddressSigner).updatePendingOwner(owner.address)
      await reserve.connect(owner).acceptOwner()
      await expect(reserve.connect(user).initialize()).to.not.be.reverted
      expect(await reserve.owner()).to.equal(owner.address)
    })

    it('accepts ownership if not DSU owner', async () => {
      dsu.owner.returns(dsu.address)
      dsu.acceptOwnership.whenCalledWith().returns()
      await expect(reserve.initialize()).to.not.be.reverted
      expect(dsu.acceptOwnership).to.have.been.called
    })

    it('reverts if not pending owner', async () => {
      dsu.owner.returns(dsu.address)
      dsu.acceptOwnership.reverts('Ownable2Step: caller is not the new owner')
      await expect(reserve.initialize()).to.be.reverted
      expect(dsu.acceptOwnership).to.have.been.called
    })
  })

  describe('#updateCoordinator', () => {
    beforeEach(async () => {
      await reserve.connect(owner).initialize()
    })

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
      await reserve.connect(owner).initialize()
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

  describe('#redeemPrice', () => {
    it('returns ONE', async () => {
      expect(await reserve.redeemPrice()).to.equal(utils.parseEther('1'))
    })
  })

  describe('#mintPrice', () => {
    it('returns ONE', async () => {
      expect(await reserve.mintPrice()).to.equal(utils.parseEther('1'))
    })
  })

  describe('#mint', () => {
    it('pulls USDC from the sender, wraps it as DSU', async () => {
      const amount = utils.parseEther('10')

      usdc.transferFrom.whenCalledWith(user.address, reserve.address, 10e6).returns(true)
      dsu.mint.whenCalledWith(amount).returns(true)
      dsu.transfer.whenCalledWith(user.address, amount).returns(true)

      await expect(reserve.connect(user).mint(amount)).to.emit(reserve, 'Mint').withArgs(user.address, amount, amount)

      expect(usdc.transferFrom).to.have.been.calledWith(user.address, reserve.address, 10e6)
      expect(dsu.mint).to.have.been.calledWith(amount)
      expect(dsu.transfer).to.have.been.calledWith(user.address, amount)
    })

    it('pulls USDC from the sender, wraps it as DSU with rounding', async () => {
      const amount = utils.parseEther('10').sub(1)

      usdc.transferFrom.whenCalledWith(user.address, reserve.address, 10e6).returns(true)
      dsu.mint.whenCalledWith(amount).returns(true)
      dsu.transfer.whenCalledWith(user.address, amount).returns(true)

      await expect(reserve.connect(user).mint(amount)).to.emit(reserve, 'Mint').withArgs(user.address, amount, amount)

      expect(usdc.transferFrom).to.have.been.calledWith(user.address, reserve.address, 10e6)
      expect(dsu.mint).to.have.been.calledWith(amount)
      expect(dsu.transfer).to.have.been.calledWith(user.address, amount)
    })
  })

  describe('#redeem', () => {
    it('pulls DSU from the sender, unwraps it to USDC', async () => {
      const amount = utils.parseEther('10')

      dsu.transferFrom.whenCalledWith(user.address, reserve.address, amount).returns(true)
      dsu.burn.whenCalledWith(amount).returns(true)
      usdc.transfer.whenCalledWith(user.address, 10e6).returns(true)

      dsu.totalSupply.whenCalledWith().returns(amount)
      usdc.balanceOf.whenCalledWith(reserve.address).returns(10e6)

      await expect(reserve.connect(user).redeem(amount))
        .to.emit(reserve, 'Redeem')
        .withArgs(user.address, amount, amount)

      expect(dsu.transferFrom).to.have.been.calledWith(user.address, reserve.address, amount)
      expect(dsu.burn).to.have.been.calledWith(amount)
      expect(usdc.transfer).to.have.been.calledWith(user.address, 10e6)
    })

    it('pulls DSU from the sender, unwraps it to USDC with roundng', async () => {
      const amount = utils.parseEther('10').add(1)

      dsu.transferFrom.whenCalledWith(user.address, reserve.address, amount).returns(true)
      dsu.burn.whenCalledWith(amount).returns(true)
      usdc.transfer.whenCalledWith(user.address, 10e6).returns(true)

      dsu.totalSupply.whenCalledWith().returns(amount)
      usdc.balanceOf.whenCalledWith(reserve.address).returns(10e6 + 1)

      await expect(reserve.connect(user).redeem(amount))
        .to.emit(reserve, 'Redeem')
        .withArgs(user.address, amount, amount)

      expect(dsu.transferFrom).to.have.been.calledWith(user.address, reserve.address, amount)
      expect(dsu.burn).to.have.been.calledWith(amount)
      expect(usdc.transfer).to.have.been.calledWith(user.address, 10e6)
    })
  })

  describe('#issue', () => {
    beforeEach(async () => {
      await reserve.connect(owner).initialize()
    })

    it('mints DSU up to collateral requirement', async () => {
      const amount = utils.parseEther('10')

      dsu.transfer.whenCalledWith(owner.address, amount).returns(true)
      dsu.mint.whenCalledWith(amount).returns(true)

      dsu.totalSupply.whenCalledWith().returns(utils.parseEther('10')) // 10 DSU
      usdc.balanceOf.whenCalledWith(reserve.address).returns(10e6 + 10e6) // 20 USDC

      await expect(reserve.connect(owner).issue(amount)).to.emit(reserve, 'Issue').withArgs(owner.address, amount)

      expect(dsu.transfer).to.have.been.calledWith(owner.address, amount)
      expect(dsu.mint).to.have.been.calledWith(amount)
    })

    it('reverts if not owner', async () => {
      const amount = utils.parseEther('10')
      await expect(reserve.connect(user).issue(amount)).to.be.revertedWithCustomError(reserve, 'OwnableNotOwnerError')
    })
  })
})
