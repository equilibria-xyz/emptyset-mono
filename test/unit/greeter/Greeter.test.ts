import { FakeContract, smock } from '@defi-wonderland/smock'
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect, use } from 'chai'
import { Signer } from 'ethers'
import HRE from 'hardhat'
import { Greeter, Registry, Greeter__factory } from '../../../types/generated'

const { ethers } = HRE
use(smock.matchers)

const GREETING = 'hello'

describe('Greeter', () => {
  let owner: Signer
  let user: Signer
  let registry: FakeContract<Registry>
  let greeter: Greeter

  const beforeFixture = async () => {
    ;[owner, user] = await ethers.getSigners()

    registry = await smock.fake<Registry>('Registry')
    greeter = await new Greeter__factory(owner).deploy(registry.address)
  }

  beforeEach(async () => {
    await loadFixture(beforeFixture)
  })

  it('Should return the greeting', async () => {
    registry.greeting.whenCalledWith().returns(GREETING)
    const greeting = await greeter.connect(user).callStatic.greet()

    await expect(greeter.connect(user).greet()).to.emit(greeter, 'Greet').withArgs(GREETING)
    expect(greeting).to.equal(GREETING)

    expect(registry.greeting).to.have.been.called
  })
})
