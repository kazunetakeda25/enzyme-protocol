import { UniswapV2PoolPriceFeed, UniswapV2PoolPriceFeedArgs, ValueInterpreter } from '@enzymefinance/protocol';
import { DeployFunction } from 'hardhat-deploy/types';

import { loadConfig } from '../../../../utils/config';

const fn: DeployFunction = async function (hre) {
  const {
    deployments: { deploy, get, log },
    ethers: { getSigners },
  } = hre;

  const deployer = (await getSigners())[0];
  const config = await loadConfig(hre);
  const fundDeployer = await get('FundDeployer');
  const valueInterpreter = await get('ValueInterpreter');

  const uniswapPoolPriceFeed = await deploy('UniswapV2PoolPriceFeed', {
    args: [fundDeployer.address, valueInterpreter.address, config.uniswap.factory] as UniswapV2PoolPriceFeedArgs,
    from: deployer.address,
    log: true,
    skipIfAlreadyDeployed: true,
  });

  // Register all uniswap pool tokens with the derivative price feed
  if (uniswapPoolPriceFeed.newlyDeployed) {
    const pools = Object.values(config.uniswap.pools);
    if (!!pools.length) {
      log('Registering UniswapV2 pool tokens');
      const uniswapPoolPriceFeedInstance = new UniswapV2PoolPriceFeed(uniswapPoolPriceFeed.address, deployer);
      await uniswapPoolPriceFeedInstance.addPoolTokens(pools);

      const valueInterpreterInstance = new ValueInterpreter(valueInterpreter.address, deployer);
      await valueInterpreterInstance.addDerivatives(
        pools,
        pools.map(() => uniswapPoolPriceFeed.address),
      );
    }
  }
};

fn.tags = ['Release', 'UniswapV2PoolPriceFeed'];
fn.dependencies = ['Config', 'FundDeployer', 'ValueInterpreter'];

export default fn;
