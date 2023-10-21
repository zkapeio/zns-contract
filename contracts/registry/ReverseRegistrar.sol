// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.4;

import "./ZNS.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract NameResolver {
    function setName(bytes32 node, string memory name) public virtual;
}

contract ReverseRegistrar is Initializable {
    // namehash('addr.reverse')
    bytes32 public constant ADDR_REVERSE_NODE =
        0x91d1777781884d03a6757a803996e38de2a42967fb37eeaca72729271025a9e2;

    ZNS public zns;
    NameResolver public defaultResolver;

    function __ReverseRegistrar_i(
        ZNS znsAddr,
        NameResolver resolverAddr
    ) public initializer {
        __ReverseRegistrar_init(znsAddr, resolverAddr);
    }

    function __ReverseRegistrar_init(
        ZNS znsAddr,
        NameResolver resolverAddr
    ) internal onlyInitializing {
        __ReverseRegistrar_init_unchained(znsAddr, resolverAddr);
    }

    function __ReverseRegistrar_init_unchained(
        ZNS znsAddr,
        NameResolver resolverAddr
    ) internal onlyInitializing {
        zns = znsAddr;
        defaultResolver = resolverAddr;

        // Assign ownership of the reverse record to our deployer
        ReverseRegistrar oldRegistrar = ReverseRegistrar(
            zns.owner(ADDR_REVERSE_NODE)
        );
        if (address(oldRegistrar) != address(0x0)) {
            oldRegistrar.claim(msg.sender);
        }
    }

    /**
     * @dev Transfers ownership of the reverse ANS record associated with the
     *      calling account.
     * @param owner The address to set as the owner of the reverse record in ANS.
     * @return The ANS node hash of the reverse record.
     */
    function claim(address owner) public returns (bytes32) {
        return claimWithResolver(owner, address(0x0));
    }

    /**
     * @dev Transfers ownership of the reverse ANS record associated with the
     *      calling account.
     * @param owner The address to set as the owner of the reverse record in ANS.
     * @param resolver The address of the resolver to set; 0 to leave unchanged.
     * @return The ANS node hash of the reverse record.
     */
    function claimWithResolver(
        address owner,
        address resolver
    ) public returns (bytes32) {
        bytes32 label = sha3HexAddress(msg.sender);
        bytes32 node = keccak256(abi.encodePacked(ADDR_REVERSE_NODE, label));
        address currentOwner = zns.owner(node);

        // Update the resolver if required
        if (resolver != address(0x0) && resolver != zns.resolver(node)) {
            // Transfer the name to us first if it's not already
            if (currentOwner != address(this)) {
                zns.setSubnodeOwner(ADDR_REVERSE_NODE, label, address(this));
                currentOwner = address(this);
            }
            zns.setResolver(node, resolver);
        }

        // Update the owner if required
        if (currentOwner != owner) {
            zns.setSubnodeOwner(ADDR_REVERSE_NODE, label, owner);
        }

        return node;
    }

    /**
     * @dev Sets the `name()` record for the reverse ANS record associated with
     * the calling account. First updates the resolver to the default reverse
     * resolver if necessary.
     * @param name The name to set for this address.
     * @return The ANS node hash of the reverse record.
     */
    function setName(string memory name) public returns (bytes32) {
        bytes32 node = claimWithResolver(
            address(this),
            address(defaultResolver)
        );
        defaultResolver.setName(node, name);
        return node;
    }

    /**
     * @dev Returns the node hash for a given account's reverse records.
     * @param addr The address to hash
     * @return The ANS node hash.
     */
    function node(address addr) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(ADDR_REVERSE_NODE, sha3HexAddress(addr))
            );
    }

    /**
     * @dev An optimised function to compute the sha3 of the lower-case
     *      hexadecimal representation of an Ethereum address.
     * @param addr The address to hash
     * @return ret The SHA3 hash of the lower-case hexadecimal encoding of the
     *         input address.
     */
    function sha3HexAddress(address addr) private pure returns (bytes32 ret) {
        addr;
        ret; // Stop warning us about unused variables
        assembly {
            let
                lookup
            := 0x3031323334353637383961626364656600000000000000000000000000000000

            for {
                let i := 40
            } gt(i, 0) {

            } {
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
                i := sub(i, 1)
                mstore8(i, byte(and(addr, 0xf), lookup))
                addr := div(addr, 0x10)
            }

            ret := keccak256(0, 40)
        }
    }
}
