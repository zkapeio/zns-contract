// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity >=0.8.4;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "./resolvers/PublicResolvers.sol";
import "./StringUtils.sol";
import "./registry/ZNS.sol";
import "./BaseRegistrarImplementation.sol";

contract TokenURIBuilder {
    using StringUtils for *;

    BaseRegistrarImplementation public nft;

    constructor(BaseRegistrarImplementation _nft) {
        nft = _nft;
    }

    function formatName(
        string memory name
    ) private pure returns (string memory) {
        uint len = name.strlen();
        if (len >= 20) {
            string memory x = name.substring(0, 19);
            return string(abi.encodePacked(x, "..."));
        }
        return name;
    }

    function tokenURI(uint256 tokenId) public view returns (string memory) {
        string[7] memory parts;
        string memory name = nft.getName(tokenId);
        string memory znsName = string(
            abi.encodePacked(name, ".", nft.baseName())
        );

        uint len = name.strlen();

        string memory displayName = string(
            abi.encodePacked(formatName(name), ".", nft.baseName())
        );
        parts[
            0
        ] = '<svg id="layer_1" data-name="layer 1" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="0 0 400 400"><defs><style>.cls-1{fill:url(#unname);}.cls-2{fill:url(#unname_2);}.cls-3{opacity:0.75;isolation:isolate;}.cls-4{fill:url(#unname_3);}.cls-5{fill:none;stroke:#00f9ff;stroke-miterlimit:10;stroke-width:2px;}.cls-6{fill:#fff;}</style><linearGradient id="unname" x1="106.21" y1="-1713.45" x2="354.39" y2="-2027.15" gradientTransform="matrix(1, 0, 0, -1, 0, -1632)" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#5b2360"/><stop offset="1" stop-color="#348bab"/></linearGradient><radialGradient id="unname_2" cx="200" cy="-1832" r="259.61" gradientTransform="matrix(1, 0, 0, -1, 0, -1632)" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#5b2360" stop-opacity="0"/><stop offset="1" stop-opacity="0.6"/></radialGradient><radialGradient id="unname_3" cx="200" cy="2234" r="41.14" gradientTransform="translate(0 -2034)" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#00edff"/><stop offset="1" stop-color="#210037"/></radialGradient></defs><rect class="cls-1" width="400" height="400"/><rect class="cls-2" width="400" height="400"/><image class="cls-3" width="118" height="164" transform="translate(141 118)" xlink:href="data:image/png;base64,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"/><rect class="cls-4" x="172" y="149" width="56" height="102"/><rect class="cls-5" x="172" y="149" width="56" height="102"/><polygon class="cls-6" points="201.2 196 194.1 196 194.1 192.1 185.6 200 194.1 207.9 194.1 202.1 201.2 196"/><polygon class="cls-6" points="198.8 204 205.9 204 205.9 207.9 214.4 200 205.9 192.1 205.9 197.9 198.8 204"/><text font-family="Arial, Helvetica, sans-serif" font-size="40" font-weight="900"  fill="white"><tspan x="50%" y="335" text-anchor="middle">';
        parts[1] = displayName;
        parts[2] = "</tspan></text></svg>";

        string memory output = string(
            abi.encodePacked(parts[0], parts[1], parts[2])
        );

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "',
                        znsName,
                        '", "description":"',
                        znsName,
                        ', an web3 domain name for zkSync.", "attributes":[{"trait_type":"Length","display_type":"number","value": "',
                        Strings.toString(len),
                        '"},{"trait_type":"Expiration Date","display_type":"date","value":"',
                        Strings.toString(nft.nameExpires(tokenId)),
                        '"}], "image": "data:image/svg+xml;base64,',
                        Base64.encode(bytes(output)),
                        '"}'
                    )
                )
            )
        );
        output = string(
            abi.encodePacked("data:application/json;base64,", json)
        );

        return output;
    }
}
