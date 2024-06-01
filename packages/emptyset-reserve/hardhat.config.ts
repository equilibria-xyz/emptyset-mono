import { dirname } from 'path'
import defaultConfig from '../common/hardhat.default.config'

const dsuDir = dirname(require.resolve('@emptyset/dsu/package.json'))

const config = defaultConfig({
  externalDeployments: {
    kovan: [`${dsuDir}/deployments/kovan`],
    goerli: [`${dsuDir}/deployments/goerli`],
    optimismGoerli: [`${dsuDir}/deployments/optimismGoerli`],
    arbitrumGoerli: [`${dsuDir}/deployments/arbitrumGoerli`],
    arbitrumSepolia: [`${dsuDir}/deployments/arbitrumSepolia`],
    baseGoerli: [`${dsuDir}/deployments/baseGoerli`],
    arbitrum: [`${dsuDir}/deployments/arbitrum`],
    optimism: [`${dsuDir}/deployments/optimism`],
    mainnet: [`${dsuDir}/deployments/mainnet`],
    base: [`${dsuDir}/deployments/base`],
    hardhat: [`${dsuDir}/deployments/mainnet`],
    localhost: [`${dsuDir}/deployments/localhost`],
  },
  dependencyPaths: [
    '@emptyset/dsu/contracts/DSU.sol',
    '@equilibria/root/attribute/CrossChainOwner/CrossChainOwner_Arbitrum.sol',
    '@equilibria/root/attribute/CrossChainOwner/CrossChainOwner_Optimism.sol',
    '@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol',
    '@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol',
  ],
})

export default config
