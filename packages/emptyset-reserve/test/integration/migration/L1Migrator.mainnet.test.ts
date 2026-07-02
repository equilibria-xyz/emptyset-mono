import { expect } from 'chai'
import HRE from 'hardhat'
import { BigNumber, Contract, utils, constants } from 'ethers'
import { smock } from '@defi-wonderland/smock'
import {
  DSU__factory,
  ERC20VotesComp,
  IERC20Metadata__factory,
  L1Migrator__factory,
  NoopFiatReserve,
  NoopFiatReserve__factory,
} from '../../../types/generated'
import { impersonate } from '../../../../common/testutil'
import { reset } from '../../../../common/testutil/time'

const { ethers, config } = HRE

const RESERVE = '0xD05aCe63789cCb35B9cE71d01e4d632a0486Da4B'
const PROXY_ROOT = '0x4d2A5E3b7831156f62C8dF47604E321cdAF35fec'
const TIMELOCK = '0x1bba92F379375387bf8F927058da14D47464cB7A'
const GOVERNOR = '0x47C61a54B1d24d571F07a79d54543231292f769b'
const DSU = '0x605D26FBd5be761089281d5cec2Ce86eeA667109'
const USDC = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48'
const CUSDC = '0x39AA39c021dfbaE8faC545936693aC917d5E7563'
const COMP = '0xc00e94Cb662C3520282E6f5717214004A7f26888'
const COMPTROLLER = '0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B'
const ESS = '0x24aE124c4CC33D6791F8E8B63520ed7107ac8b3e'
const TWO_WAY_BATCHER = '0xAEf566ca7E84d1E736f999765a804687f39D9094'
const WRAP_ONLY_BATCHER = '0x0B663CeaCEF01f2f88EB7451C70Aa069f19dB997'
const OLD_RESERVE_IMPL = '0x363aF3acFfEd0B7181C2E3c56C00922E142100a8'

const IMPLEMENTATION_SLOT = '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc'
const LEGACY_OWNER_SLOT = utils.keccak256(utils.toUtf8Bytes('emptyset.v2.implementation.owner'))
const LEGACY_REGISTRY_SLOT = utils.keccak256(utils.toUtf8Bytes('emptyset.v2.implementation.registry'))
const LEGACY_NOT_ENTERED_SLOT = utils.keccak256(utils.toUtf8Bytes('emptyset.v2.implementation.notEntered'))
const LEGACY_PAUSER_SLOT = utils.keccak256(utils.toUtf8Bytes('emptyset.v2.implementation.pauser'))
const LEGACY_PAUSED_SLOT = utils.keccak256(utils.toUtf8Bytes('emptyset.v2.implementation.paused'))
const ROOT_OWNER_SLOT = utils.keccak256(utils.toUtf8Bytes('equilibria.root.Ownable.owner'))
const ROOT_PENDING_OWNER_SLOT = utils.keccak256(utils.toUtf8Bytes('equilibria.root.Ownable.pendingOwner'))
const ROOT_INITIALIZER_VERSION_SLOT = utils.keccak256(utils.toUtf8Bytes('equilibria.root.Initializable.version'))
const ROOT_INITIALIZER_INITIALIZING_SLOT = utils.keccak256(
  utils.toUtf8Bytes('equilibria.root.Initializable.initializing'),
)
const RESERVE_BASE_COORDINATOR_SLOT = utils.hexZeroPad('0x00', 32)
const RESERVE_BASE_ALLOCATION_SLOT = utils.hexZeroPad('0x01', 32)
const LEGACY_TOTAL_DEBT_SLOT = RESERVE_BASE_COORDINATOR_SLOT
const LEGACY_DEBT_SLOT = RESERVE_BASE_ALLOCATION_SLOT
const LEGACY_ORDERS_SLOT = utils.hexZeroPad('0x02', 32)

const GOVERNOR_ABI = [
  'function propose(address[] targets,uint256[] values,string[] signatures,bytes[] calldatas,string description) returns (uint256)',
  'function castVote(uint256 proposalId,bool support)',
  'function queue(uint256 proposalId)',
  'function execute(uint256 proposalId) payable',
  'function proposals(uint256 proposalId) view returns (uint256 id,address proposer,uint256 eta,uint256 startBlock,uint256 endBlock,uint256 forVotes,uint256 againstVotes,bool canceled,bool executed)',
  'function proposalThreshold() view returns (uint256)',
  'function quorumVotes() view returns (uint256)',
  'function state(uint256 proposalId) view returns (uint8)',
]

const TIMELOCK_ABI = ['function delay() view returns (uint256)']

const COMPTROLLER_ABI = [
  'function compAccrued(address) view returns (uint256)',
  'function compSpeeds(address) view returns (uint256)',
  'function compSupplySpeeds(address) view returns (uint256)',
]

const maybeDescribe =
  process.env.FORK_ENABLED === 'true' && process.env.FORK_NETWORK === 'mainnet' ? describe : describe.skip

maybeDescribe('L1Migrator mainnet proposal', () => {
  async function mineToBlock(blockNumber: BigNumber): Promise<void> {
    const currentBlock = await ethers.provider.getBlockNumber()
    if (blockNumber.lte(currentBlock)) return

    await ethers.provider.send('hardhat_mine', [utils.hexValue(blockNumber.sub(currentBlock))])
  }

  async function increaseToTimestamp(timestamp: BigNumber): Promise<void> {
    const currentBlock = await ethers.provider.getBlock('latest')
    if (timestamp.lte(currentBlock.timestamp)) return

    await ethers.provider.send('evm_increaseTime', [timestamp.sub(currentBlock.timestamp).toNumber()])
    await ethers.provider.send('evm_mine', [])
  }

  async function setGovernorStake(stake: string): Promise<void> {
    await ethers.provider.send('hardhat_setStorageAt', [GOVERNOR, utils.hexValue(1), utils.hexZeroPad(stake, 32)])
  }

  function mappingSlot(account: string, slot: number): string {
    return utils.keccak256(utils.defaultAbiCoder.encode(['address', 'uint256'], [account, slot]))
  }

  function orderSlots(makerToken: string, takerToken: string): [string, string] {
    const innerSlot = mappingSlot(makerToken, 2)
    const priceSlot = utils.keccak256(utils.defaultAbiCoder.encode(['address', 'uint256'], [takerToken, innerSlot]))
    const amountSlot = BigNumber.from(priceSlot).add(1).toHexString()

    return [priceSlot, utils.hexZeroPad(amountSlot, 32)]
  }

  async function expectStorageZero(slot: string): Promise<void> {
    expect(await ethers.provider.getStorageAt(RESERVE, slot)).to.equal(constants.HashZero)
  }

  async function storageValue(slot: string): Promise<BigNumber> {
    return BigNumber.from(await ethers.provider.getStorageAt(RESERVE, slot))
  }

  async function expectStorageAddress(slot: string, address: string): Promise<void> {
    expect(await ethers.provider.getStorageAt(RESERVE, slot)).to.equal(utils.hexZeroPad(address, 32).toLowerCase())
  }

  beforeEach(async () => {
    await reset(config)
  })

  it('passes governance, executes atomically, and leaves the reserve in noop state', async () => {
    const [deployer, proposer, voter, user] = await ethers.getSigners()
    const dsu = DSU__factory.connect(DSU, deployer)
    const usdc = IERC20Metadata__factory.connect(USDC, deployer)
    const cUsdc = IERC20Metadata__factory.connect(CUSDC, deployer)
    const comp = IERC20Metadata__factory.connect(COMP, deployer)
    const ess = IERC20Metadata__factory.connect(ESS, deployer)
    const governor = new Contract(GOVERNOR, GOVERNOR_ABI, proposer)
    const timelock = new Contract(TIMELOCK, TIMELOCK_ABI, deployer)
    const comptroller = new Contract(COMPTROLLER, COMPTROLLER_ABI, deployer)

    const finalReserve = await new NoopFiatReserve__factory(deployer).deploy(DSU, USDC)
    const migrator = await new L1Migrator__factory(deployer).deploy()

    const mockStake = await smock.fake<ERC20VotesComp>('ERC20VotesComp')
    const quorumVotes = await governor.quorumVotes()
    mockStake.getPriorVotes.returns(quorumVotes)
    await setGovernorStake(mockStake.address)

    const preTotalSupply = await dsu.totalSupply()
    const preReserveDsu = await dsu.balanceOf(RESERVE)
    const preReserveUsdc = await usdc.balanceOf(RESERVE)
    const preReserveComp = await comp.balanceOf(RESERVE)
    const preReserveEss = await ess.balanceOf(RESERVE)
    const preTimelockEss = await ess.balanceOf(TIMELOCK)
    const preEssTotalSupply = await ess.totalSupply()
    const preTwoWayDsu = await dsu.balanceOf(TWO_WAY_BATCHER)
    const preTwoWayUsdc = await usdc.balanceOf(TWO_WAY_BATCHER)
    const preReserveCUsdc = await cUsdc.balanceOf(RESERVE)
    const twoWayDebtSlot = mappingSlot(TWO_WAY_BATCHER, 1)
    const wrapOnlyDebtSlot = mappingSlot(WRAP_ONLY_BATCHER, 1)
    const cUsdcEssOrderSlots = orderSlots(CUSDC, ESS)
    const compEssOrderSlots = orderSlots(COMP, ESS)
    const preTotalDebt = await storageValue(LEGACY_TOTAL_DEBT_SLOT)
    const preTwoWayDebt = await storageValue(twoWayDebtSlot)
    const preWrapOnlyDebt = await storageValue(wrapOnlyDebtSlot)

    await expectStorageAddress(IMPLEMENTATION_SLOT, OLD_RESERVE_IMPL)
    await expectStorageAddress(LEGACY_OWNER_SLOT, TIMELOCK)
    expect(await dsu.owner()).to.equal(RESERVE)
    expect(await comptroller.compAccrued(RESERVE)).to.equal(0)
    expect(await comptroller.compSpeeds(CUSDC)).to.equal(0)
    expect(await comptroller.compSupplySpeeds(CUSDC)).to.equal(0)
    expect(preTwoWayDsu).to.be.gt(0)
    expect(preReserveCUsdc).to.be.gt(0)
    expect(preReserveEss).to.be.gt(0)
    expect(preTimelockEss).to.be.gt(0)
    expect(preTotalDebt).to.be.gt(0)
    expect(preTwoWayDebt).to.be.gt(0)
    expect(preTotalDebt).to.equal(preTwoWayDebt.add(preWrapOnlyDebt))
    expect(await ethers.provider.getStorageAt(RESERVE, cUsdcEssOrderSlots[0])).to.not.equal(constants.HashZero)
    expect(await ethers.provider.getStorageAt(RESERVE, cUsdcEssOrderSlots[1])).to.not.equal(constants.HashZero)
    expect(await ethers.provider.getStorageAt(RESERVE, compEssOrderSlots[0])).to.not.equal(constants.HashZero)
    expect(await ethers.provider.getStorageAt(RESERVE, compEssOrderSlots[1])).to.not.equal(constants.HashZero)

    const initializeData = migrator.interface.encodeFunctionData('initialize')
    const targets = [ESS, PROXY_ROOT, PROXY_ROOT]
    const values = [0, 0, 0]
    const signatures = [
      'transfer(address,uint256)',
      'upgradeAndCall(address,address,bytes)',
      'upgrade(address,address)',
    ]
    const calldatas = [
      utils.defaultAbiCoder.encode(['address', 'uint256'], [RESERVE, preTimelockEss]),
      utils.defaultAbiCoder.encode(['address', 'address', 'bytes'], [RESERVE, migrator.address, initializeData]),
      utils.defaultAbiCoder.encode(['address', 'address'], [RESERVE, finalReserve.address]),
    ]

    const proposalId = await governor
      .connect(proposer)
      .callStatic.propose(targets, values, signatures, calldatas, 'Wind down DSU reserve debt integrations')
    await governor
      .connect(proposer)
      .propose(targets, values, signatures, calldatas, 'Wind down DSU reserve debt integrations')

    let proposal = await governor.proposals(proposalId)
    await mineToBlock(proposal.startBlock.add(1))
    expect(await governor.state(proposalId)).to.equal(1) // Active

    await governor.connect(voter).castVote(proposalId, true)

    proposal = await governor.proposals(proposalId)
    await mineToBlock(proposal.endBlock.add(1))
    expect(await governor.state(proposalId)).to.equal(4) // Succeeded

    await governor.connect(proposer).queue(proposalId)
    proposal = await governor.proposals(proposalId)
    await increaseToTimestamp(
      proposal.eta
        .add(await timelock.delay())
        .sub(await timelock.delay())
        .add(1),
    )
    expect(await governor.state(proposalId)).to.equal(5) // Queued

    await governor.connect(proposer).execute(proposalId)
    expect(await governor.state(proposalId)).to.equal(7) // Executed

    const reserve = NoopFiatReserve__factory.connect(RESERVE, deployer) as NoopFiatReserve
    const postReserveUsdc = await usdc.balanceOf(RESERVE)

    await expectStorageAddress(IMPLEMENTATION_SLOT, finalReserve.address)
    expect(await cUsdc.balanceOf(RESERVE)).to.equal(0)
    expect(await dsu.balanceOf(RESERVE)).to.equal(0)
    expect(await dsu.balanceOf(TWO_WAY_BATCHER)).to.equal(0)
    expect(await usdc.balanceOf(TWO_WAY_BATCHER)).to.equal(0)
    expect(await dsu.totalSupply()).to.equal(preTotalSupply.sub(preTwoWayDsu).sub(preReserveDsu))
    expect(await ess.balanceOf(RESERVE)).to.equal(0)
    expect(await ess.balanceOf(TIMELOCK)).to.equal(0)
    expect(await ess.totalSupply()).to.equal(preEssTotalSupply.sub(preReserveEss).sub(preTimelockEss))
    expect(postReserveUsdc).to.be.gt(preReserveUsdc.add(preTwoWayUsdc))
    expect(await comp.balanceOf(RESERVE)).to.equal(preReserveComp)

    await expectStorageZero(LEGACY_TOTAL_DEBT_SLOT)
    await expectStorageZero(LEGACY_DEBT_SLOT)
    await expectStorageZero(LEGACY_ORDERS_SLOT)
    await expectStorageZero(twoWayDebtSlot)
    await expectStorageZero(wrapOnlyDebtSlot)
    await expectStorageZero(cUsdcEssOrderSlots[0])
    await expectStorageZero(cUsdcEssOrderSlots[1])
    await expectStorageZero(compEssOrderSlots[0])
    await expectStorageZero(compEssOrderSlots[1])
    await expectStorageZero(LEGACY_OWNER_SLOT)
    await expectStorageZero(LEGACY_REGISTRY_SLOT)
    await expectStorageZero(LEGACY_NOT_ENTERED_SLOT)
    await expectStorageZero(LEGACY_PAUSER_SLOT)
    await expectStorageZero(LEGACY_PAUSED_SLOT)

    await expectStorageAddress(ROOT_OWNER_SLOT, TIMELOCK)
    await expectStorageZero(ROOT_PENDING_OWNER_SLOT)
    expect(await ethers.provider.getStorageAt(RESERVE, ROOT_INITIALIZER_VERSION_SLOT)).to.equal(
      utils.hexZeroPad('0x02', 32),
    )
    await expectStorageZero(ROOT_INITIALIZER_INITIALIZING_SLOT)

    expect(await reserve.owner()).to.equal(TIMELOCK)
    expect(await reserve.coordinator()).to.equal(constants.AddressZero)
    expect(await reserve.allocation()).to.equal(0)
    expect(await reserve.dsu()).to.equal(DSU)
    expect(await reserve.fiat()).to.equal(USDC)
    expect(await reserve.assets()).to.equal(postReserveUsdc.mul(1e12))
    expect(await reserve.mintPrice()).to.equal(utils.parseEther('1'))
    expect(await reserve.redeemPrice()).to.equal(utils.parseEther('1'))

    await expect(
      deployer.sendTransaction({
        to: RESERVE,
        data:
          utils.id('borrow(address,uint256)').slice(0, 10) +
          utils.defaultAbiCoder.encode(['address', 'uint256'], [user.address, 1]).slice(2),
      }),
    ).to.be.reverted

    const reserveSigner = await impersonate.impersonateWithBalance(RESERVE, utils.parseEther('10'))
    await usdc.connect(reserveSigner).transfer(user.address, 100e6)
    await usdc.connect(user).approve(RESERVE, constants.MaxUint256)
    await dsu.connect(user).approve(RESERVE, constants.MaxUint256)

    await reserve.connect(user).mint(utils.parseEther('10'))
    expect(await dsu.balanceOf(user.address)).to.equal(utils.parseEther('10'))

    await reserve.connect(user).redeem(utils.parseEther('4'))
    expect(await dsu.balanceOf(user.address)).to.equal(utils.parseEther('6'))
    expect(await usdc.balanceOf(user.address)).to.equal(94e6)
  })
})
