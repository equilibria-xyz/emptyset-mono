import { loadFixture } from '@nomicfoundation/hardhat-network-helpers'
import { expect } from 'chai'
import { Signer } from 'ethers'
import HRE from 'hardhat'
import { Registry, Registry__factory } from '../../../types/generated'

const { ethers } = HRE

const GREETING = 'hello'

describe('Registry', () => {
  let owner: Signer
  let user: Signer
  let registry: Registry

  const beforeFixture = async () => {
    ;[owner, user] = await ethers.getSigners()

    registry = await new Registry__factory(owner).deploy()
  }

  beforeEach(async () => {
    await loadFixture(beforeFixture)
  })

  it('should properly update greeting', async () => {
    await expect(registry.connect(user).updateGreeting(GREETING))
      .to.emit(registry, 'GreetingUpdated')
      .withArgs(GREETING)

    expect(await registry.connect(user).greeting()).to.equal(GREETING)
  })
})
