// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.6.0 <0.9.0;

interface IConvexBaseRewardPool {
    function addExtraReward(address _reward) external returns (bool success_);

    function extraRewards(uint256 _index) external view returns (address extraRewardPool_);

    function rewardManager() external view returns (address rewardManager_);
}
