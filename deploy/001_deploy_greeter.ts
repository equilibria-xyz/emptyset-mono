import { HardhatRuntimeEnvironment } from 'hardhat/types'
import { DeployFunction } from 'hardhat-deploy/types'
import { Registry, Registry__factory } from '../types/generated'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

const GREETING = 'hello'

const func: DeployFunction = async function (hre: HardhatRuntimeEnvironment) {
  const { deployments, getNamedAccounts, ethers } = hre
  const { deploy, get } = deployments
  const { deployer } = await getNamedAccounts()
  const deployerSigner: SignerWithAddress = await ethers.getSigner(deployer)

  await deploy('Registry', {
    from: deployer,
    skipIfAlreadyDeployed: true,
    log: true,
    autoMine: true,
  })

  const registry: Registry = new Registry__factory(deployerSigner).attach((await get('Registry')).address)

  if ((await registry.greeting()) == GREETING) {
    console.log('Registry already initialized.')
  } else {
    process.stdout.write('initializing Registry... ')
    await (await registry.updateGreeting(GREETING)).wait(2)
    process.stdout.write('complete.\n')
  }

  await deploy('Greeter', {
    from: deployer,
    args: [registry.address],
    skipIfAlreadyDeployed: true,
    log: true,
    autoMine: true,
  })
}

export default func
func.tags = ['Greeter']
