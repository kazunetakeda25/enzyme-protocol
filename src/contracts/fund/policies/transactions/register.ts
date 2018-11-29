import { Address } from '@melonproject/token-math/address';

import { getFunctionABISignature } from '~/utils/abi/getFunctionABISignature';
import {
  transactionFactory,
  PrepareArgsFunction,
  EnhancedExecute,
} from '~/utils/solidity/transactionFactory';
import { Contracts, requireMap } from '~/Contracts';

const genericExchangeInterfaceABI = requireMap[Contracts.GenericExchange];
const participationABI = requireMap[Contracts.Participation];

export enum PolicedMethods {
  makeOrder = getFunctionABISignature(genericExchangeInterfaceABI, 'makeOrder'),
  takeOrder = getFunctionABISignature(genericExchangeInterfaceABI, 'takeOrder'),
  // tslint:disable-next-line:max-line-length
  executeRequest = getFunctionABISignature(
    participationABI,
    'executeRequestFor',
  ),
  // TODO: Add more here
}

interface RegisterArgs {
  method: PolicedMethods;
  policy: Address;
}

const prepareArgs: PrepareArgsFunction<RegisterArgs> = async ({
  method,
  policy,
}: RegisterArgs) => [method, `${policy}`];

const register: EnhancedExecute<RegisterArgs, boolean> = transactionFactory(
  'register',
  Contracts.PolicyManager,
  undefined,
  prepareArgs,
);

export { register };
