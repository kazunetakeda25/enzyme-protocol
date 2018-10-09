pragma solidity ^0.4.21;
pragma experimental ABIEncoderV2;

import "./ExchangeAdapterInterface.sol";
import "../thirdparty/0x/Exchange.sol";
import "../../Fund.sol";
import "../../dependencies/DBC.sol";
import "../../dependencies/math.sol";


/// @title ZeroExV2Adapter Contract
/// @author Melonport AG <team@melonport.com>
/// @notice Adapter between Melon and 0x Exchange Contract (version 1)
contract ZeroExV2Adapter is ExchangeAdapterInterface, DSMath, DBC, Asset, LibAbiEncoder {

    //  METHODS

    //  PUBLIC METHODS

    /// @notice Make order not implemented for smart contracts in this exchange version
    function makeOrder(
        address targetExchange,
        address[6] orderAddresses,
        uint[8] orderValues,
        bytes32 identifier,
        bytes makerAssetData,
        bytes takerAssetData,
        bytes signature
    ) {
        revert();
    }

    // Responsibilities of takeOrder are:
    // - check sender
    // - check fund not shut down
    // - check not buying own fund tokens
    // - check price exists for asset pair
    // - check price is recent
    // - check price passes risk management
    // - approve funds to be traded (if necessary)
    // - take order from the exchange
    // - check order was taken (if possible)
    // - place asset in ownedAssets if not already tracked
    /// @notice Takes an active order on the selected exchange
    /// @dev These orders are expected to settle immediately
    /// @param targetExchange Address of the exchange
    /// @param orderAddresses [0] Order maker
    /// @param orderAddresses [1] Order taker
    /// @param orderAddresses [2] Order maker asset
    /// @param orderAddresses [3] Order taker asset
    /// @param orderAddresses [4] feeRecipientAddress
    /// @param orderAddresses [5] senderAddress
    /// @param orderValues [0] makerAssetAmount
    /// @param orderValues [1] takerAssetAmount
    /// @param orderValues [2] Maker fee
    /// @param orderValues [3] Taker fee
    /// @param orderValues [4] expirationTimeSeconds
    /// @param orderValues [5] Salt/nonce
    /// @param orderValues [6] Fill amount: amount of taker token to be traded
    /// @param orderValues [7] Dexy signature mode
    /// @param identifier Order identifier
    /// @param makerAssetData Encoded data specific to makerAsset.
    /// @param takerAssetData Encoded data specific to takerAsset.
    /// @param signature Signature of the order.
    function takeOrder(
        address targetExchange,
        address[6] orderAddresses,
        uint[8] orderValues,
        bytes32 identifier,
        bytes makerAssetData,
        bytes takerAssetData,
        bytes signature
    ) {
        require(Fund(address(this)).owner() == msg.sender);
        require(!Fund(address(this)).isShutDown());

        address makerAsset = orderAddresses[3];
        address takerAsset = orderAddresses[4];
        uint maxMakerQuantity = orderValues[0];
        uint maxTakerQuantity = orderValues[1];
        uint fillTakerQuantity = orderValues[6];
        uint fillMakerQuantity = mul(fillTakerQuantity, maxMakerQuantity) / maxTakerQuantity;

        require(takeOrderPermitted(fillTakerQuantity, takerAsset, fillMakerQuantity, makerAsset));
        
        approveTakerAsset(targetExchange, takerAsset, takerAssetData, fillTakerQuantity);
        uint takerAssetFilledAmount = constructAndExecuteFill(targetExchange, orderAddresses, orderValues, makerAssetData, takerAssetData, fillTakerQuantity, signature);
        // require(takerAssetFilledAmount == fillTakerQuantity);
        // require(
        //     Fund(address(this)).isInAssetList(makerAsset) ||
        //     Fund(address(this)).getOwnedAssetsLength() < Fund(address(this)).MAX_FUND_ASSETS()
        // );

        // Fund(address(this)).addAssetToOwnedAssets(makerAsset);
        // Fund(address(this)).orderUpdateHook(
        //     targetExchange,
        //     bytes32(identifier),
        //     Fund.UpdateType.take,
        //     [makerAsset, takerAsset],
        //     [maxMakerQuantity, maxTakerQuantity, fillTakerQuantity]
        // );
    }

    /// @notice Cancel is not implemented on exchange for smart contracts
    function cancelOrder(
        address targetExchange,
        address[6] orderAddresses,
        uint[8] orderValues,
        bytes32 identifier,
        bytes makerAssetData,
        bytes takerAssetData,
        bytes signature
    ) {
        revert();
    }

    // TODO: delete this function if possible
    function getLastOrderId(address targetExchange)
        view
        returns (uint)
    {
        revert();
    }

    // TODO: delete this function if possible
    function getOrder(address targetExchange, uint id)
        view
        returns (address, address, uint, uint)
    {
        revert();
    }

    // INTERNAL METHODS


    /// @notice needed to avoid stack too deep error
    function approveTakerAsset(address targetExchange, address takerAsset, bytes takerAssetData, uint fillTakerQuantity)
        view
        returns (address)
    {
        bytes4 assetProxyId;
        assembly {
            assetProxyId := and(mload(
                add(takerAssetData, 32)),
                0xFFFFFFFF00000000000000000000000000000000000000000000000000000000
            )
        }
        address assetProxy = Exchange(targetExchange).getAssetProxy(assetProxyId);

        require(Asset(takerAsset).approve(assetProxy, fillTakerQuantity));
    }

    /// @dev needed to avoid stack too deep error
    function constructAndExecuteFill(
        address targetExchange,
        address[6] orderAddresses,
        uint[8] orderValues,
        bytes makerAssetData,
        bytes takerAssetData,
        uint256 takerAssetFillAmount,
        bytes signature
    )
        internal
        returns (uint)
    {
        // uint takerFee = orderValues[3];
        // TODO: Disable for now
        // if (takerFee > 0) {
        //     Token zeroExToken = Token(Exchange(targetExchange).ZRX_TOKEN_CONTRACT());
        //     require(zeroExToken.approve(Exchange(targetExchange).TOKEN_TRANSFER_PROXY_CONTRACT(), takerFee));
        // }
        LibFillResults.FillResults memory fillResults;
        
        LibOrder.Order memory order = LibOrder.Order({
            makerAddress: orderAddresses[0],
            takerAddress: orderAddresses[1],
            feeRecipientAddress: orderAddresses[2],
            senderAddress: orderAddresses[3],
            makerAssetAmount: orderValues[0],
            takerAssetAmount: orderValues[1],
            makerFee: orderValues[2],
            takerFee: orderValues[3],
            expirationTimeSeconds: orderValues[4],
            salt: orderValues[5],
            makerAssetData: makerAssetData,
            takerAssetData: takerAssetData
        });

        // ABI encode calldata for `fillOrder`
        bytes memory fillOrderCalldata = abiEncodeFillOrder(
            order,
            takerAssetFillAmount,
            signature
        );

        // Call `fillOrder` and handle any exceptions gracefully
        fillResults = executeFill(targetExchange, fillOrderCalldata);
        return fillResults.takerAssetFilledAmount;
    }
    
    /// @dev needed to avoid stack too deep error
    function executeFill(
        address targetExchange,
        bytes fillOrderCalldata
    )
        internal
        returns (LibFillResults.FillResults memory fillResults)
    {
        // uint takerFee = orderValues[3];
        // TODO: Disable for now
        // if (takerFee > 0) {
        //     Token zeroExToken = Token(Exchange(targetExchange).ZRX_TOKEN_CONTRACT());
        //     require(zeroExToken.approve(Exchange(targetExchange).TOKEN_TRANSFER_PROXY_CONTRACT(), takerFee));
        // }
        
        // Call `fillOrder` and handle any exceptions gracefully
        bool success;
        assembly {
            success := call(
                gas,                                // forward all gas
                targetExchange,                     // call address of Exchange contract
                0,                                  // transfer 0 wei
                add(fillOrderCalldata, 32),         // pointer to start of input (skip array length in first 32 bytes)
                mload(fillOrderCalldata),           // length of input
                fillOrderCalldata,                  // write output over input
                128                                 // output size is 128 bytes
            )
            if success {
                mstore(fillResults, mload(fillOrderCalldata))
                mstore(add(fillResults, 32), mload(add(fillOrderCalldata, 32)))
                mstore(add(fillResults, 64), mload(add(fillOrderCalldata, 64)))
                mstore(add(fillResults, 96), mload(add(fillOrderCalldata, 96)))
            }
        }

        require(success);
        // fillResults values will be 0 by default if call was unsuccessful
        // return 1;
    }

    // VIEW METHODS

    /// @dev needed to avoid stack too deep error
    function takeOrderPermitted(
        uint takerQuantity,
        address takerAsset,
        uint makerQuantity,
        address makerAsset
    )
        internal
        view
        returns (bool)
    {
        require(takerAsset != address(this) && makerAsset != address(this));
        require(makerAsset != takerAsset);
        // require(fillTakerQuantity <= maxTakerQuantity);
        var (pricefeed, , riskmgmt) = Fund(address(this)).modules();
        require(pricefeed.existsPriceOnAssetPair(takerAsset, makerAsset));
        var (isRecent, referencePrice, ) = pricefeed.getReferencePriceInfo(takerAsset, makerAsset);
        require(isRecent);
        uint orderPrice = pricefeed.getOrderPriceInfo(
            takerAsset,
            makerAsset,
            takerQuantity,
            makerQuantity
        );
        return(
            riskmgmt.isTakePermitted(
                orderPrice,
                referencePrice,
                takerAsset,
                makerAsset,
                takerQuantity,
                makerQuantity
            )
        );
    }
}
